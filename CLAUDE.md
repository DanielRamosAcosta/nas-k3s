# CLAUDE.md

Este archivo proporciona orientación a Claude Code (claude.ai/code) al trabajar con el código de este repositorio.

## Visión general del proyecto

Infraestructura-como-código de un homelab K3s usando **Jsonnet + Tanka** para despliegues declarativos de Kubernetes en un NAS personal. Gestiona un stack self-hosted: aplicaciones de medios, bases de datos, monitorización, autenticación y servicios de sistema.

## Herramientas disponibles

- **jq** — Disponible para inspeccionar/transformar JSON (p. ej. `tk eval ... | jq '.field'`)
- **skopeo** — Disponible para buscar la versión adecuada de una imagen Docker.

## Seguridad

**NUNCA pases secretos a través del contexto de Claude. NUNCA.** Esto incluye claves privadas, contraseñas, claves de API, tokens, secretos de cliente OIDC, o cualquier otro valor sensible — no los imprimas, no hagas echo, no los pegues en un prompt, ni los incluyas en argumentos de herramientas donde quedarían capturados en la conversación.

Cuando necesites generar claves/secretos:

1. **Redirige siempre la salida a un archivo** en lugar de imprimirla en stdout (donde acabaría en el contexto).
   ```bash
   # MAL — el secreto acaba en el contexto de Claude:
   openssl rand -base64 32

   # BIEN — el secreto va a un archivo, nunca se muestra:
   openssl rand -base64 32 > /tmp/secret.txt
   ```
2. **Canaliza el archivo hacia el comando que lo consume** (p. ej. el script de cifrado) sin leer nunca su contenido:
   ```bash
   cat /tmp/secret.txt | ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>
   ```
3. **Elimina el archivo inmediatamente después de usarlo — esto es crítico.**
   ```bash
   rm -f /tmp/secret.txt
   ```

Solo la salida cifrada (SealedSecret) es segura para commitear y para mostrar. El secreto en texto plano nunca debe leerse con la herramienta Read, imprimirse ni exponerse de ninguna otra forma en la conversación.

## Añadir un nuevo servicio: minimizar la configuración

**Comprueba siempre los valores por defecto antes de escribir configuración.** La tendencia es copiar una configuración generada completa e incluirlo todo — esto genera ruido y dificulta detectar los valores reales que no son por defecto.

Antes de escribir `homeserver.yaml`, `config.yaml`, o cualquier archivo de configuración de un servicio:

1. Lee la documentación oficial o la configuración por defecto que genera la imagen (`--generate-config`, `-e`, dry-run, etc.) para saber cuáles son realmente los valores por defecto.
2. Incluye solo valores que difieran del valor por defecto, que sea obligatorio establecer explícitamente (p. ej. `report_stats` en Synapse), o que tengan una razón concreta para especificarse.
3. Para rutas (directorio de datos, signing key, media store, etc.) — comprueba si es viable montar en la ruta por defecto antes de añadir una sobreescritura en la configuración.
4. Para la configuración de listener/red — comprueba qué campos tienen valores por defecto sensatos (`tls: false`, `type: http`) frente a cuáles realmente hay que establecer (`bind_addresses`, `x_forwarded`).

Un archivo de configuración con 10 líneas donde cada línea importa es mejor que 40 líneas donde 30 son valores por defecto.

### Usuario de ejecución del contenedor (`runAsUser`)

**Cuando la doc/imagen de un servicio indica el uid con el que está pensada para correr, fija `runAsUser` (y `runAsGroup`/`fsGroup`) a ese uid en el pod por defecto** — especialmente si montas un ConfigMap/Secret **read-only** dentro de un directorio propio de la imagen (config, etc.).

Muchas imágenes arrancan su entrypoint **como root** y hacen un `chown -R` sobre sus directorios. Si ahí dentro hay un montaje read-only, el `chown` falla; con `set -e` el entrypoint **aborta antes de loguear nada** → el contenedor sale con código 1 y **cero logs** (síntoma engañoso, parece un fallo de arranque del propio servicio). Correr como el uid de la app salta ese bloque de `chown`.

Caso real: `apache/couchdb` (corre como uid 5984) — montar nuestro `local.ini` read-only provocaba CrashLoopBackOff sin logs hasta fijar `runAsUser: 5984`. Si además el hostPath de datos lo crea root, usa un init container `runAsUser: 0` solo para el `chown` de ese volumen.

## Observabilidad: logs

**Consulta siempre los logs vía Loki a través del servidor MCP `grafanaSelfHosted`. NO uses `kubectl logs` para inspeccionar logs.**

Loki agrega los logs de cada pod del clúster y permite filtrar por rango de tiempo, nivel y patrón sin necesidad de que el pod siga existiendo. `kubectl logs` solo ve la instancia de contenedor actual y pierde el historial en los reinicios.

Flujo típico:
1. `mcp__grafanaSelfHosted__list_datasources` con `type: loki` → obtén el `uid` del datasource (actualmente `P8E80F9AEF21F6940`).
2. `mcp__grafanaSelfHosted__query_loki_logs` con un selector LogQL. Etiquetas útiles: `namespace`, `pod`, `container`, `service_name`, `level`.
   - Ejemplo: `{namespace="media", pod=~"immich.*"} |~ "(?i)error|warn|fail"`
3. Si no estás seguro de las etiquetas, usa `list_loki_label_values` (p. ej. `labelName: namespace`) antes de consultar.
4. Para flujos ruidosos, prefiere `query_loki_patterns` o `find_error_pattern_logs` para agrupar errores.

Chuleta de namespaces: `argocd`, `arr`, `business`, `communications`, `databases`, `kube-system`, `media`, `monitoring`, `system`. (Las apps se agrupan por categoría, no por namespace propio de cada app — p. ej. immich vive en `media`, no en `immich`.)

`kubectl logs` solo es aceptable como último recurso cuando el propio Loki/Promtail está roto.

## Comandos clave

```bash
# Sealed Secrets
echo -n 'value' | ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>  # Ámbito estricto
echo -n 'value' | ./scripts/encrypt-secret.sh --cluster-wide                     # Ámbito cluster-wide

# Dependencias de Jsonnet
jb install              # Instala las dependencias de jsonnet-bundler en vendor/

# Flujo de Tanka
tk eval environments/<category>                        # Compila Jsonnet a JSON
tk export dist/ environments/ --recursive --format '{{index .metadata.labels "app"}}/{{.kind}}-{{.metadata.name}}'  # Exporta todos los manifiestos

# Despliegue (GitOps vía ArgoCD — NUNCA uses tk apply directamente)
# 1. Commit + push a main
# 2. CI exporta los manifiestos a la rama 'manifests'
# 3. ArgoCD detecta los cambios → sincroniza manualmente desde la UI o la CLI
argocd app sync <app-name> --grpc-web                  # Sincroniza una sola app
```

### Conexión con el clúster (port-forward SSH)

Si falla la conexión con el clúster (p. ej. `kubectl`/`tk` no llegan al API server en `localhost:6443`), revisa primero si el puerto está redirigido. Si no lo está, abre el túnel SSH:

```bash
ssh -fN -L 6443:localhost:6443 nas
```

## Arquitectura

### Toolchain
- **Tanka (tk)** - Herramienta de despliegue de Kubernetes construida sobre Jsonnet
- **Jsonnet** - Lenguaje de plantillas de datos (todos los manifiestos de K8s se generan a partir de archivos .libsonnet)
- **jsonnet-bundler (jb)** - Gestor de dependencias para librerías de Jsonnet
- **k8s-libsonnet 1.29** - Bindings tipados de la API de Kubernetes vía `lib/k.libsonnet`

### Estructura de directorios
- **`lib/`** - Librerías de Jsonnet que definen cada aplicación. Cada app es un módulo `.libsonnet` con una factory `new(version)` que devuelve todos sus recursos de K8s (StatefulSet/Deployment, Service, ConfigMap, Secret, IngressRoute).
  - `utils.libsonnet` - Helpers compartidos para volúmenes hostPath, secretos, config maps, ingress routes, RBAC, volume mounts y middleware de Traefik
  - `<appname>.secrets.json` - Valores de secretos cifrados con Kubeseal (en gitignore), uno por app junto a su `.libsonnet`
  - Subdirectorios: `arr/`, `auth/`, `databases/`, `media/`, `monitoring/`, `system/`
- **`environments/`** - Definiciones de entornos de Tanka. Cada uno tiene `main.jsonnet` (importa librerías, conecta versiones) + `spec.json` (namespace, API server).
  - `versions.json` - Versiones centralizadas de las imágenes de contenedor de todas las apps
- **`dist/`** - Manifiestos YAML generados (en gitignore, salida de `tk export`)
- **`charts/`** - Helm charts vendorizados (Traefik, K8s Dashboard) gestionados vía `chartfile.yaml`
- **`vendor/`** - Dependencias de Jsonnet (en gitignore, instaladas vía `jb install`)

### Patrón de módulo de app

Toda app en `lib/` sigue este patrón:

```jsonnet
local secrets = import 'category/appname.secrets.json';
{
  new():: {
    local this = self,
    statefulset: /* o deployment */,
    service: /* Service ClusterIP */,
    config_map: /* config de la app vía importstr */,
    sealed_secret: u.sealedSecret.forEnv(self.statefulset, secrets.appname),
    ingress_route: u.ingressRoute.from(this.service, 'app.domain.com'),
    // los volúmenes son hostPath, definidos inline en el spec del statefulset/deployment:
    // volume.fromHostPath('data', '/data/appname'),
  }
}
```

Los entornos componen estos módulos en `main.jsonnet`, pasando las versiones desde `versions.json`.

### Red y autenticación
- **Traefik** como ingress controller con CRDs IngressRoute y TLS de Let's Encrypt
- **Authelia** proporciona OIDC/forward-auth; el middleware se aplica vía `utils.traefik.middleware`
- Los servicios se comunican internamente vía DNS de Kubernetes (`svc.cluster.local`)

### Almacenamiento
- Todos los volúmenes usan **hostPath** directamente (sin PV/PVC) — más simple para un homelab NAS de un solo nodo
- Rutas de datos: `/data/*` (SSD, estado de apps) y `/cold-data/*` (HDD, medios/backups)
- Helper: `u.volume.fromHostPath(name, path)` o `volume.fromHostPath(name, path)` de k8s-libsonnet

### Secretos (Sealed Secrets)

Todos los servicios usan **Bitnami Sealed Secrets**. El controlador corre en `kube-system` y descifra los recursos `SealedSecret` en recursos `Secret` normales dentro del clúster.

#### Ámbitos de cifrado

| Ámbito | Cuándo usarlo | Comando de cifrado |
|-------|-------------|-----------------|
| **strict** | Secretos específicos de un servicio (claves de API, secretos de cliente OIDC) | `echo -n 'value' \| ./scripts/encrypt-secret.sh <namespace> <sealed-secret-name>` |
| **cluster-wide** | Secretos compartidos (contraseñas de BD, SMTP) reutilizados entre namespaces | `echo -n 'value' \| ./scripts/encrypt-secret.sh --cluster-wide` |

**Importante**: No puedes mezclar valores cifrados en ámbito strict y cluster-wide en el mismo recurso SealedSecret. Usa recursos separados (p. ej. `sealed_secret` + `sealed_secret_shared`).

#### Estructura del archivo de secretos

Los datos cifrados viven en archivos `<appname>.secrets.json` junto a cada `.libsonnet`:
```json
{
  "serviceName": {
    "SECRET_KEY": "kubeseal-encrypted-value"
  },
  "shared": {
    "DB_PASSWORD": "kubeseal-encrypted-value-cluster-wide"
  }
}
```

#### API de Utils

**Ámbito strict** (específico de un servicio):
- `u.sealedSecret.forEnv(component, encryptedData)` — SealedSecret con nombre derivado del componente
- `u.sealedSecret.forEnvNamed(name, encryptedData)` — SealedSecret con nombre explícito
- `u.sealedSecret.forFile(fileName, encryptedValue)` — SealedSecret para montar como archivo

**Ámbito cluster-wide** (compartido entre namespaces):
- `u.sealedSecret.wide.forEnv(component, encryptedData)`
- `u.sealedSecret.wide.forEnvNamed(name, encryptedData)`
- `u.sealedSecret.wide.forFile(fileName, encryptedValue)`

**Referenciar secretos**:
- `u.envVars.fromSealedSecret(sealedSecret)` — genera referencias de variables de entorno
- `u.volumeMount.fromSealedSecretFile(sealedSecret, path)` — monta un archivo desde un SealedSecret
- `u.volume.fromSealedSecret(sealedSecret)` — volumen que referencia el Secret descifrado

#### Patrón: Config con secretos embebidos (merge con jq)

Para apps que necesitan un archivo de configuración que mezcla config pública + secretos (p. ej. invidious, immich):

1. **ConfigMap** con la config pública (visible en git)
2. **SealedSecret** con solo los campos secretos como archivo JSON
3. **Init container** con `jq` que hace un deep-merge de ambos: `jq -s '.[0] * .[1]' public.json secret.json > merged.json`
4. **Contenedor principal** lee el resultado fusionado

```jsonnet
invidiousConfigPublic: u.configMap.forFile('invidious-config.json', std.manifestJsonEx(config, '  ')),
invidiousConfigSecret: u.sealedSecret.wide.forFile('invidious-config-secret.json', secrets.configSecretFile),
// el init container fusiona ambos, el contenedor principal lee vía variable de entorno o montaje de archivo
```

### ArgoCD

ArgoCD gestiona todos los despliegues vía GitOps. Vive en `environments/argocd/` con namespace `argocd`.

#### Arquitectura
- **CI** exporta los manifiestos a la rama `manifests` en cada push a main
- **ArgoCD** lee los YAMLs desde la rama `manifests` (sin plugins/sidecars)
- **Webhook** notifica a ArgoCD en cada push para detección instantánea (sin polling)
- **Sincronización manual** — ArgoCD detecta el drift pero NO lo aplica automáticamente

#### Los cambios de config reinician los pods automáticamente (Reloader) — NO hagas `kubectl rollout restart` a mano

**Stakater Reloader está instalado a nivel de clúster y se encarga de esto por ti. Nunca reinicies un pod manualmente solo para recoger un cambio de ConfigMap/Secret.**

`u.labelApp()` (vía `u.Environment`, en `lib/utils/core.libsonnet`) estampa automáticamente cada Deployment/StatefulSet/DaemonSet con la anotación `reloader.stakater.com/auto: "true"`. Reloader vigila los ConfigMaps/Secrets que cada workload referencia y **reinicia el pod automáticamente (en unos segundos) cada vez que su contenido cambia** — incluyendo plantillas de config renderizadas con envsubst como `synapse-homeserver-tpl`.

Consecuencia para el flujo de despliegue: un cambio que solo afecta a un ConfigMap/Secret (sin cambio en el spec del Deployment) reinicia el pod por sí solo. Tras `/deploy`, basta con esperar a que ArgoCD sincronice el nuevo ConfigMap; Reloader reinicia el workload. Confirma vía los logs de Reloader (`{namespace="kube-system", pod=~"reloader.*"}` en Loki — busca "Changes detected in '<configmap>' ... updated '<workload>'") en lugar de reiniciar a mano.

#### Applications
Una Application por servicio (no por namespace). Se generan dinámicamente en `argocd/main.jsonnet` importando todos los demás entornos y extrayendo las etiquetas `app` de los recursos. Al añadir un nuevo servicio, basta con añadirlo al `main.jsonnet` del entorno con `u.labelApp()` y ArgoCD lo recoge automáticamente.

#### OIDC
ArgoCD usa Authelia para SSO. Los client IDs y el secret se almacenan en el SealedSecret `argocd-oidc-secret` y se referencian desde `argocd-cm` con la sintaxis `$argocd-oidc-secret:key-name`. El `argocd-secret` (con `server.secretkey` y `webhook.github.secret`) también es un SealedSecret — el `createSecret` del Helm chart está deshabilitado.

#### CRÍTICO: Eliminar Applications de ArgoCD

**NUNCA uses `argocd app delete <name>` sin `--cascade=false`**. Por defecto, eliminar una Application también elimina TODOS los recursos del clúster que gestiona (prune). Esto tirará servicios.

```bash
# MAL — elimina del clúster todos los recursos gestionados por la app:
argocd app delete myapp -y

# BIEN — solo elimina el recurso Application, mantiene los recursos del clúster:
argocd app delete myapp --cascade=false
```

#### Server-Side Apply
La Application `argocd` usa `syncOptions: [ServerSideApply=true]` porque el CRD `applicationsets` supera el límite de 262KB de anotación para el apply del lado cliente.

## Preguntas y decisiones

Cuando pidas una decisión al usuario y tengas análisis suficiente para inclinar la balanza, **marca la opción que recomiendas con "(Recomendado)" y da el porqué en una frase** — no presentes las opciones de forma totalmente neutral obligando al usuario a reconstruir el trade-off. Reserva la neutralidad para cuando de verdad no haya una recomendación defendible.

## Gestión del proyecto

Todo el trabajo se gestiona en **Backlog.md** (archivos de tarea bajo `backlog/tasks/`).

### Reglas

1. **NUNCA trabajar sin ticket.** Ten siempre una o más tareas en `in_progress` que representen el trabajo actual. Si no existe ninguna, encuentra o pregunta al usuario para crear la tarea apropiada antes de empezar.
2. **Creación vs Edición**: Para crear, usamos la skill `create-task`. Para editar, editamos el markdown a mano usando el formato adecuado.
3. **Flujo de finalización.** Cuando una tarea esté terminada, confírmalo con el usuario. Solo tras su aprobación explícita: establece `status: Done` y commitea.
4. **Nunca te auto-apruebes.** No muevas tareas a `Done` ni commitees sin el OK explícito del usuario.

### Finalizar tareas (a mano)

Al terminar una tarea, edita su archivo markdown y establece `status: Done` en el frontmatter. NO archives el archivo ni lo muevas fuera de `backlog/tasks/` — las tareas permanecen en su sitio. No uses ninguna herramienta MCP de escritura para esto.
