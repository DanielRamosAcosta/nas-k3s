---
id: NASKS-82
title: Desplegar servidor de Minecraft (Paper) con backups GFS
status: Done
assignee: []
created_date: '2026-07-22 20:32'
updated_date: '2026-08-07 17:26'
labels: []
dependencies: []
references:
  - >-
    /Users/danielramos/Documents/repos/infra/system/backlog/docs/doc-6 -
    Hardware-Placa-Base-CWWK-CW-AT-10G-8P-CPU-Intel-N355.md
  - >-
    /Users/danielramos/Documents/repos/infra/system/backlog/docs/doc-7 -
    Hardware-RAM-Crucial-DDR5-32GB-SO-DIMM.md
  - 'https://github.com/itzg/mc-router'
  - 'https://github.com/itzg/docker-minecraft-server'
  - 'https://github.com/itzg/docker-mc-backup'
priority: low
type: feature
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Desplegar un servidor de Minecraft (Paper) en el clúster K3s para 2-3 jugadores ocasionales, siguiendo el patrón de módulos del repo, más un CronJob que haga backups del mundo con rotación GFS (Grandfather-Father-Son) copiando de SSD a HDD.

## 🎯 Contexto funcional

Se quiere un servidor de Minecraft self-hosted para jugar de forma ocasional entre 2-3 personas. El NAS tiene margen de sobra para ello (ver Contexto técnico). Además, el mundo es dato valioso e irremplazable, por lo que necesita backups automáticos con retención escalonada (GFS) para poder recuperar tanto un estado reciente como uno de hace semanas/meses.

> **Nota (2026-07-24):** decisiones de diseño cerradas en sesión de grill-me. Cambios respecto al planteamiento original: namespace **`games`** dedicado (no `media`); exposición vía **`LoadBalancer` de mc-router** (no `IngressRouteTCP` de Traefik); backups con **`itzg/mc-backup` + método restic** (GFS nativo, no script propio); **sin whitelist** (open-join asumido); permisos de hostPath por **chown manual vía SSH** (no init container).

### Viabilidad (análisis previo)

Specs del NAS: CPU Intel N355 (8C/8T, turbo 3.9 GHz single-core, AVX2), 32 GB DDR5, NVMe en `/data`. Uso real medido (VictoriaMetrics, 7 días): CPU media ~13-21% sobre 8 cores con picos transitorios; ~20 GB de RAM disponibles de forma estable. Minecraft es mayormente single-thread (game loop: tick + generación de chunks); para 2-3 jugadores un core turbo a 3.9 GHz sobra y hay RAM de sobra. Conclusión: el NAS lo aguanta holgadamente.

### Ubicación

- Namespace **dedicado `games`** (nuevo environment `environments/games/` + `lib/games/`, más una entrada en `argocd/main.jsonnet`). ArgoCD crea el namespace vía `CreateNamespace=true`. Motivo: mc-router vive en la cara expuesta y su auto-discovery **obliga** a `list/watch` de Services/StatefulSets (no acotable por `resourceNames`); un ns dedicado que solo contiene Minecraft hace que ese permiso inevitable sea intrínsecamente vacío de cualquier otro recurso.

### Servidor

- Módulo `.libsonnet` siguiendo el patrón del repo: **StatefulSet** (no Deployment — mc-router escala StatefulSets 0↔1) + Service ClusterIP + volumen hostPath en `/data/minecraft` (NVMe, no HDD, para latencia de carga/gen de chunks). Requisito de mc-router: `StatefulSet.metadata.name` **==** `StatefulSet.spec.serviceName` (p. ej. ambos `minecraft`), o el autoscaling no dispara.
- Imagen base **`itzg/minecraft-server:java25`** con `TYPE=PAPER`, **`VERSION=26.2`**. La versión de Minecraft/Paper cambió a numeración por año; **26.2 es la última** (Paper aún en canal beta a fecha de hoy) y exige **Java 25** (de ahí el tag `:java25`). Se configura 100% por env vars. Centralizar en `versions.json` tanto el tag de imagen como `VERSION`; además **pinnear el build de Paper** (`PAPER_BUILD`) para reproducibilidad, ya que el server re-verifica Paper en cada arranque (y con scale-to-zero arranca en cada wake).
- Heap fijo **4G** (`MEMORY=4G` → `-Xms4G -Xmx4G`) + flags recomendados de Paper/Aikar (`USE_AIKAR_FLAGS=true`). No sobreasignar heap.
- Recursos: memoria **request=limit=6Gi** (QoS Guaranteed: nunca desalojado, sin riesgo de OOMKill; 4G heap + ~1.5G de overhead JVM/Paper). CPU **request 1, sin limit** (un CPU limit throttlea el game loop → tick lag; con el server casi siempre dormido y 2-3 jugadores no ahoga el stack).
- `terminationGracePeriodSeconds` holgado (~90s): al escalar 1→0, Paper recibe SIGTERM y necesita tiempo para guardar el mundo limpio (base de la consistencia de backups + del `.paused`).
- Exposición del puerto 25565 (TCP crudo, no HTTP) vía el **`LoadBalancer` de mc-router** (ver más abajo).

### Scale-to-zero (sleep/wake on join) con mc-router

- **[mc-router](https://github.com/itzg/mc-router)** como proxy delante del servidor: apaga el server cuando nadie juega (StatefulSet a 0 réplicas) y lo levanta bajo demanda (0→1) al recibir una conexión, escalándolo de nuevo a 0 tras un periodo de inactividad. Ahorra CPU/RAM cuando el server está ocioso (lo habitual para 2-3 jugadores ocasionales).
- Es la opción nativa de Kubernetes (habla el API para escalar el StatefulSet real), frente a alternativas orientadas a Docker/proceso como `lazymc`. Requiere **RBAC** (ver Seguridad).
- **Exposición del 25565 directa por el `Service` de mc-router en modo `LoadBalancer`** (klipper/svclb de k3s), **sin Traefik en medio**: el TCP crudo de Minecraft no lleva TLS/SNI, así que Traefik no aportaría ningún control (Crowdsec/geoblock/auth no aplican a TCP crudo) y solo añadiría un salto de proxy y un entrypoint dedicado. mc-router ya es el único punto de entrada y el que hace el wake.
- Descubrimiento: mc-router corre con `-in-kube-cluster` y descubre el backend por anotación del Service del server (`mc-router.itzg.me/defaultServer: "true"` — un solo backend, enruta todo). El puerto del Service debe llamarse `minecraft`.
- Tunables: `-auto-scale-up`/`-auto-scale-down`; **wait-timeout en el default (60s)** de momento (a subir si el arranque en frío molesta); **down-after 1h** (jugadores ocasionales; coste de 1h ociosa despreciable en este NAS); MOTDs personalizados dormido/arrancando.
- El scale-to-zero es transparente para los backups: el mundo persiste en el hostPath `/data/minecraft` aunque el StatefulSet esté a 0 réplicas.

### Backups (restic + GFS, vía mc-backup)

- **`itzg/mc-backup`** (mismo autor) como **CronJob de K8s** (one-shot), **diario 05:00**, corriendo como **uid 1000**. Monta `/data/minecraft` **read-only** (SRC) y `/cold-data/minecraft` **read-write** (DEST, SSD→HDD).
- Método **`restic`** con retención **GFS nativa**: `PRUNE_RESTIC_RETENTION="--keep-daily 7 --keep-weekly 4 --keep-monthly 6"`. restic aporta dedup + incrementales + integridad por checksums + cifrado (repo en `/cold-data/minecraft`, `RESTIC_PASSWORD` en SealedSecret). Restore vía runbook `restic restore` (análogo al de Postgres).
- **Consistencia sin depender del server encendido**: mc-backup solo hace `save-off/save-all flush` por RCON si el server está arriba; si detecta el fichero **`.paused`** en SRC, salta RCON y snapshotea los ficheros directamente. Como con scale-to-zero el server está apagado casi siempre (parada limpia = mundo consistente en disco), cableamos el marcador en el lifecycle del StatefulSet: `preStop` → `touch /data/minecraft/.paused`; arranque → `rm -f`. Resultado: server dormido → snapshot file-only consistente; alguien jugando → flush por RCON y luego snapshot.

### Seguridad

- **Exposición en TCP crudo, sin Authelia**: el protocolo de Minecraft es TCP puro (25565), así que **no se puede aplicar el forward-auth de Authelia** del resto del stack. La seguridad recae en los controles propios de Minecraft. Cualquiera que conozca el dominio/IP puede hablar con el server → asumido en el diseño.
- **`online-mode=true`** (innegociable: en `false` cualquiera puede suplantar a cualquier usuario, incluidos ops). `OPS=Duning` en ConfigMap.
- **Sin whitelist (decisión consciente — open-join)**: se descarta la whitelist para **no depender del operador** para dar acceso. `online-mode=true` solo autentica identidad, **no restringe quién entra**: cualquier cuenta legítima que descubra el server (y el 25565 se escanea masivamente) puede unirse. Se acepta este riesgo a cambio de la comodidad; **evolución futura**: plugin de invitación/allowlist auto-gestionado por los jugadores.
- **RCON**: habilitado (lo necesita mc-backup en el camino "server encendido"). Contraseña en **SealedSecret** (compartida server↔mc-backup, no la default `minecraft`). Puerto **25575 solo ClusterIP**, nunca expuesto por el LoadBalancer.
- **RBAC de mc-router con mínimo privilegio**: `ServiceAccount` + **`Role` namespaced en `games`** (no `ClusterRole`) + `RoleBinding`, y mc-router arrancado con `-kube-namespace=games` (`KUBE_NAMESPACE` vía `fieldRef`) para mirar solo su ns. Reglas: `services` `[list,watch]` y `statefulsets` `[list,watch]` (inevitables para el auto-discovery, **no acotables** por `resourceNames`) + `statefulsets`/`statefulsets/scale` `[get,update,patch]` **acotado con `resourceNames: [minecraft]`** (el poder mutante restringido al único STS). Como `games` solo contiene Minecraft, el `list/watch` inevitable no revela nada más, y lo único modificable es escalar el propio Minecraft.
- **Hardening del pod (radio de explosión de un RCE tipo Log4Shell)**: `runAsNonRoot: true` (uid 1000), `capabilities.drop: ["ALL"]`, sin `privileged`, `readOnlyRootFilesystem: true`, `seccompProfile.type: RuntimeDefault`. `emptyDir` en `/tmp` (escritura efímera con rootfs RO); todo lo demás (mundo, jars, logs, config) va al hostPath en `/data`. Montar **solo** el hostPath `/data/minecraft`. Es la postura por defecto de la propia chart de itzg, así que la imagen la soporta.

### Pre-flight (requisitos manuales previos al despliegue)

- **Permisos de hostPath (chown manual por SSH, una vez)**: `chown 1000:1000` de `/data/minecraft` y `/cold-data/minecraft`. Se elige chown manual en lugar de init container. Sin esto, ni el server no-root escribe el mundo ni mc-backup escribe el repo restic.
- **NAT del router**: redirigir **TCP 25565** → IP del NAS (donde el `LoadBalancer` de mc-router publica el puerto). Sin esto, ningún jugador externo alcanza el server.
- **DNS `mc.danielramos.me`** (lo gestiona el usuario): registro **A gris (DNS-only), NO proxied** — la nube naranja de Cloudflare solo proxya HTTP/HTTPS y rompe el TCP crudo. ⚠️ La IP de casa es dinámica: un registro estático se quedará obsoleto al cambiar la IP; para mantenerlo al día habría que gestionarlo con el `cloudflare-ddns` (soporta `PROXIED` por-dominio con expresión, p. ej. `PROXIED=is(nas.danielramos.me)`). (Opcional futuro: frontal tipo TCPShield/playit.gg para no exponer la IP de casa.)
<!-- SECTION:DESCRIPTION:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
> **Regla de ejecución (petición explícita del usuario):** el plan se divide en **Parte A — Implementación** (escribir TODO el código del clúster, sin desplegar ni commitear) y **Parte B — Rollout** (despliegues por fases, tras aprobación). **Al terminar la Parte A hay un CHECKPOINT DE REVISIÓN DURO: parar, el usuario revisa todo el código antes de cualquier deploy/commit.** Durante la Parte A no se ejecuta `/deploy`, ni `git commit`, ni `git push`, ni `argocd sync`.

### Estructura objetivo de ficheros

```
environments/games/spec.json                       # namespace games
environments/games/main.jsonnet                    # compone las apps
lib/games/minecraft/minecraft.libsonnet            # app: minecraft (server)
lib/games/minecraft/minecraft.secrets.json         # RCON (valores cifrados; SE COMMITEA)
lib/games/mc-router/mc-router.libsonnet            # app: mc-router (proxy + LB + RBAC)
lib/games/minecraft-backup/minecraft-backup.libsonnet   # app: minecraft-backup (CronJob)
lib/games/minecraft-backup/minecraft-backup.secrets.json # RESTIC (valores cifrados; SE COMMITEA)
```
> Nota: en este repo los `*.secrets.json` **NO están en `.gitignore` y SÍ se commitean** — solo contienen valores ya cifrados por kubeseal, seguros en git (como los 10+ existentes).
Tres apps de ArgoCD (una por servicio, según convención del repo): `minecraft`, `mc-router`, `minecraft-backup`, todas en ns `games`.

### Fase 0 — Prerrequisitos manuales (YA HECHOS, solo verificar)
- ✅ `chown 1000:1000` de `/data/minecraft` y `/cold-data/minecraft` en el NAS.
- ✅ DNS `mc.danielramos.me` (A gris) dado de alta por el usuario.
- ✅ NAT del router: TCP 25565 → 192.168.1.200 (NAS).

---

## PARTE A — Implementación (sin desplegar)

### Fase A1 — Scaffold del environment `games` + `versions.json`
1. Crear `environments/games/spec.json` (copia de `environments/media/spec.json` con `namespace: "games"` y `metadata.name: "environments/games"`).
2. Añadir a `lib/versions.json` (valores ya verificados con `skopeo list-tags` y la API de Paper; re-confirmar por si han avanzado):
   ```json
   "minecraft":  { "image": "docker.io/itzg/minecraft-server", "version": "java25", "paperVersion": "26.2", "paperBuild": "65" },
   "mcRouter":   { "image": "docker.io/itzg/mc-router", "version": "1.45.0" },
   "mcBackup":   { "image": "docker.io/itzg/mc-backup", "version": "2026.7.2" }
   ```
   (`java25` existe como tag; `paperBuild=65` es el último de 26.2, canal BETA; `mc-router 1.45.0` y `mc-backup 2026.7.2` son los últimos estables.)
3. Los `lib/games/**/**.secrets.json` se crearán en A2 y **se commitean** (valores cifrados) — NO tocar `.gitignore`.
4. **NO desplegar.** Checkpoint: `tk eval environments/games` fallará aún (falta main.jsonnet) — es esperado; solo validar que `versions.json` parsea (`jq . lib/versions.json`).

### Fase A2 — Secretos (generar + cifrar, local; NO toca el clúster)
> Seguir CLAUDE.md: nunca imprimir secretos; redirigir a fichero temporal, canalizar a `encrypt-secret.sh`, borrar.
1. RCON (strict, ns `games`, nombre `minecraft-rcon`):
   ```bash
   openssl rand -base64 24 > /tmp/rcon.txt
   cat /tmp/rcon.txt | ./scripts/encrypt-secret.sh games minecraft-rcon   # → pegar en minecraft.secrets.json bajo clave RCON_PASSWORD
   rm -f /tmp/rcon.txt
   ```
2. RESTIC (strict, ns `games`, nombre `minecraft-restic`):
   ```bash
   openssl rand -base64 32 > /tmp/restic.txt
   # ⚠️ AVISAR AL USUARIO ANTES DE BORRAR: que guarde el contenido de /tmp/restic.txt en su
   #    gestor de contraseñas. Es la ÚNICA copia fuera de banda; sin ella, un clúster muerto
   #    dejaría el repo restic de /cold-data irrecuperable (el SealedSecret solo lo descifra el clúster).
   cat /tmp/restic.txt | ./scripts/encrypt-secret.sh games minecraft-restic   # → minecraft-backup.secrets.json bajo clave RESTIC_PASSWORD
   rm -f /tmp/restic.txt
   ```
3. Crear `lib/games/minecraft/minecraft.secrets.json` = `{ "minecraftRcon": { "RCON_PASSWORD": "<enc>" } }` y `lib/games/minecraft-backup/minecraft-backup.secrets.json` = `{ "minecraftRestic": { "RESTIC_PASSWORD": "<enc>" } }`.
4. **NO desplegar.** (El cifrado solo produce datos cifrados en ficheros locales; nada llega al clúster.)

### Fase A3 — Módulo del servidor (`lib/games/minecraft/minecraft.libsonnet`)
Patrón estándar (`u`, `versions`, `k`). Recursos:
- **StatefulSet `minecraft`** (imagen `itzg/minecraft-server:java25`):
  - **Omitir `spec.replicas` del manifiesto** (técnica concreta): `statefulSet.new('minecraft', 1, [...])` fuerza `replicas: 1`; **ocultarlo** componiendo `+ { spec+: { replicas:: null } }` (el campo oculto `::` desaparece del JSON manifestado → `tk eval` no emite `replicas`). Con Server-Side Apply ArgoCD no gestiona el campo y no revierte el escalado de mc-router. Comentar el porqué en el código.
  - **Fijar `spec.serviceName`**: `+ statefulSet.spec.withServiceName('minecraft')` (por defecto sale `null`; mc-router exige `serviceName == metadata.name == "minecraft"`).
  - `terminationGracePeriodSeconds: 90`.
  - Puertos del contenedor: `minecraft` (25565), `rcon` (25575).
  - Env desde ConfigMap (nombres verificados en la doc de itzg): `EULA=TRUE`, `TYPE=PAPER`, `VERSION=<paperVersion>`, `PAPER_BUILD=<paperBuild>`, **`PAPER_CHANNEL=experimental`** (obligatorio: 26.2 solo tiene builds beta; sin esto itzg falla con "No build found ... with channel 'default'"), `MEMORY=4G` (fija `Xms=Xmx`), `USE_AIKAR_FLAGS=true`, `ONLINE_MODE=TRUE`, `OPS=Duning`, `EXISTING_OPS_FILE=SYNCHRONIZE` (mantiene `OPS` como fuente de verdad declarativa), `RCON_PORT=25575`, `TZ=Atlantic/Canary` (el NAS está en Canarias). RCON ya viene **habilitado por defecto** (no hace falta `ENABLE_RCON`). **No** setear `WHITELIST` → sin whitelist.
  - Env desde SealedSecret `minecraft-rcon`: `RCON_PASSWORD`.
  - Recursos: `requests/limits` memoria `6Gi` (iguales), CPU `requests: 1` sin `limits`.
  - **securityContext contenedor**: `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile.type: RuntimeDefault`.
  - **securityContext pod**: `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 1000`.
  - **lifecycle**: `preStop.exec: ["/bin/sh","-c","touch /data/.paused"]`; `postStart.exec: ["/bin/sh","-c","rm -f /data/.paused"]`.
  - **Volúmenes**: `hostPath /data/minecraft` → `/data`; `emptyDir` → `/tmp`.
  - Probe: `u.probes.stateful.tcp(25565)` (readiness+startup, sin liveness; `failureThreshold` alto del preset cubre el arranque en frío que descarga Paper y genera mundo).
- **Service `minecraft`** (ClusterIP): usar **`k.util.serviceFor(self.statefulSet, nameFormat='%(port)s')`** — el default `%(container)s-%(port)s` produciría `minecraft-minecraft`, pero mc-router (y el AC#4) exigen el puerto llamado **`minecraft`**. Expone 25565 (`minecraft`) y 25575 (`rcon`), ambos internos. Anotar el Service con `mc-router.itzg.me/defaultServer: "true"`.
- **SealedSecret** `minecraft-rcon` (`u.sealedSecret.forEnvNamed('minecraft-rcon', secrets.minecraftRcon)`).
- **ConfigMap** de env (`u.configMap.forEnv(...)`).
- **NO desplegar.** Checkpoint: se compone en A6.

### Fase A4 — Módulo mc-router + RBAC + LoadBalancer (`lib/games/mc-router/mc-router.libsonnet`)
- **ServiceAccount `mc-router`**.
- **Role `mc-router` (namespaced en `games`)** + **RoleBinding** (escritos a mano con `k.rbac.v1.role`/`roleBinding` — el helper `u.rbac` crea *ClusterRole*, no sirve). Reglas:
  - `["" ] services [list, watch]`
  - `["apps"] statefulsets [list, watch]`
  - `["apps"] statefulsets, statefulsets/scale [get, update, patch]` con `resourceNames: ["minecraft"]`
- **Deployment `mc-router`** (imagen `itzg/mc-router:<tag>`):
  - `serviceAccountName: mc-router`.
  - Env `KUBE_NAMESPACE` vía `fieldRef` a `metadata.namespace`.
  - Args/flags: `--in-kube-cluster --auto-scale-up --auto-scale-down --auto-scale-down-after=1h` (+ MOTDs `--auto-scale-asleep-motd` / `--auto-scale-loading-motd`; wait-timeout en default 60s). Verificar en la doc si el flag es `--kube-namespace` o basta la env `KUBE_NAMESPACE`.
  - ⚠️ **UX del primer wake**: el cliente Java corta la conexión ~30s; el primer arranque en frío (descarga Paper + genera mundo) puede superarlo → ese primer intento requerirá **reintentar la conexión** (el server ya estará arrancando). Aceptado por el usuario ("ya veremos" con el default). Si molesta, bajar wait-timeout o pre-generar el mundo en B1.
  - Puerto contenedor `minecraft` (25565).
  - securityContext endurecido análogo (no-root, drop ALL, RO rootfs, seccomp) — mc-router es un binario Go estático, tolera bien RO rootfs.
- **Service `mc-router` tipo LoadBalancer**: `k.util.serviceFor(self.deployment) + service.spec.withType('LoadBalancer')`, puerto 25565. (klipper/svclb de k3s publica el puerto en el nodo → NAT lo alcanza.)
- **NO desplegar.**

### Fase A5 — Módulo backup (`lib/games/minecraft-backup/minecraft-backup.libsonnet`)
- **CronJob `minecraft-backup`** (imagen `itzg/mc-backup:<tag>`, `schedule: "0 5 * * *"`):
  - `restartPolicy: OnFailure`, `concurrencyPolicy: Forbid`, history limits 3/3.
  - **securityContext pod**: `runAsUser: 1000`, `runAsGroup: 1000`.
  - Env ConfigMap: `BACKUP_METHOD=restic`, `SRC_DIR=/data`, `RESTIC_REPOSITORY=/backups`, `BACKUP_INTERVAL=0` (one-shot: corre una vez y sale), `PRUNE_RESTIC_RETENTION=--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, `RCON_HOST=minecraft`, `RCON_PORT=25575`, `BACKUP_NAME=minecraft`.
  - Env Secret: `RESTIC_PASSWORD` (de `minecraft-restic`) y `RCON_PASSWORD` (referencia por nombre al Secret `minecraft-rcon`, con `secretKeyRef` manual — la SealedSecret la posee la app `minecraft`).
  - Volúmenes: `hostPath /data/minecraft` → `/data` **read-only** (SRC); `hostPath /cold-data/minecraft` → `/backups` **read-write** (repo restic).
- **SealedSecret** `minecraft-restic`.
- **NO desplegar.**

### Fase A6 — Composición y verificación de compilación
1. `environments/games/main.jsonnet`:
   ```jsonnet
   local minecraft = import 'games/minecraft/minecraft.libsonnet';
   local mcRouter = import 'games/mc-router/mc-router.libsonnet';
   local minecraftBackup = import 'games/minecraft-backup/minecraft-backup.libsonnet';
   local u = import 'utils.libsonnet';
   u.Environment({
     minecraft: minecraft.new(),
     mcRouter: mcRouter.new(),
     minecraftBackup: minecraftBackup.new(),
   })
   ```
2. Añadir a `environments/argocd/main.jsonnet` la línea `u.argocd.env(import '../games/spec.json', import '../games/main.jsonnet'),`.
3. **Checkpoint de compilación (sin desplegar):**
   - `jb install` si hiciera falta.
   - `tk eval environments/games` compila sin errores.
   - `tk eval environments/games | jq '[.. | objects | select(has("kind")) | .kind] | sort | unique'` muestra: StatefulSet, Service (x2, uno LoadBalancer), Deployment, CronJob, Role, RoleBinding, ServiceAccount, SealedSecret (x2), ConfigMap.
   - Verificar que el StatefulSet **no** tiene `spec.replicas`, que el Service de mc-router es `type: LoadBalancer`, que el Role es `kind: Role` (no ClusterRole) con `resourceNames: [minecraft]` solo en la regla mutante.
   - `tk eval environments/argocd | jq '[.. | objects | select(.kind=="Application") | .metadata.name]'` incluye `minecraft`, `mc-router`, `minecraft-backup`.

### ⛔ CHECKPOINT DE REVISIÓN (PARAR AQUÍ)
Todo el código del clúster está escrito y compila. **Parar. El usuario revisa todo el código.** No continuar a la Parte B (deploy/commit) sin su OK explícito.

---

## PARTE B — Rollout (tras aprobación; despliegues por fases)

> El rollout se hace por fases activando servicios en `environments/games/main.jsonnet` de forma incremental (los módulos ya están escritos y revisados). **Cada fase B implica un commit que edita `main.jsonnet` añadiendo una app** (B1 arranca solo con `minecraft`; B2 añade `mcRouter`; B3 añade `minecraftBackup`). Como `argocd/main.jsonnet` genera las Applications a partir de `games/main.jsonnet`, cada app aparece en ArgoCD solo cuando se añade. Cada fase termina con `/deploy` explícito + verificación antes de la siguiente. **Orden importante**: B1 (minecraft) antes que B3 (backup), porque el CronJob de backup referencia el Secret `minecraft-rcon` que crea la app `minecraft`.

### Fase B1 — Desplegar solo el servidor
1. Dejar en `main.jsonnet` solo `{ minecraft: minecraft.new() }` (comentar mc-router y backup).
2. **Desplegar** con la skill `/deploy`.
3. Checkpoint (vía Loki en Grafana MCP, `{namespace="games"}`): el pod arranca, descarga Paper 26.2, genera el mundo y queda escuchando; RCON arriba. `readOnlyRootFilesystem` no rompe (si peta por escritura, añadir el `emptyDir`/ruta que falte y redeploy). Confirmar en el NAS que `/data/minecraft` se puebla.

### Fase B2 — Desplegar mc-router + exposición
1. Añadir `mcRouter: mcRouter.new()` a `main.jsonnet`.
2. **Desplegar** con la skill `/deploy`.
3. Checkpoint:
   - El Service `mc-router` obtiene IP de LoadBalancer y publica 25565 en el nodo.
   - Un cliente de Minecraft (26.2) conecta a `mc.danielramos.me` y **juega** (AC#7).
   - Scale-to-zero: tras 1h ocioso (o forzando `kubectl scale --replicas=0` para la prueba) el server queda a 0; al conectar, mc-router lo despierta (0→1) y entra. Verificar que ArgoCD **no** revierte el `replicas` (gracias a omitirlo del manifiesto).

### Fase B3 — Desplegar el backup
1. Añadir `minecraftBackup: minecraftBackup.new()` a `main.jsonnet`.
2. **Desplegar** con la skill `/deploy`.
3. Checkpoint:
   - Lanzar el job a mano: `kubectl -n games create job --from=cronjob/minecraft-backup mc-backup-test`.
   - Con el server dormido (`.paused` presente) → snapshot file-only sin RCON; con el server encendido → flush por RCON. Verificar ambos caminos en logs (Loki).
   - En el NAS, `restic -r /cold-data/minecraft snapshots` (con `RESTIC_PASSWORD`) lista el snapshot. Confirmar que la retención GFS se aplica.

### Cierre
- Marcar los AC cumplidos y el DoD.
- Confirmar con el usuario antes de `status: Done` (regla de CLAUDE.md).
<!-- SECTION:PLAN:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Existe un namespace/environment dedicado `games` (environments/games/ + lib/games/ + entrada en argocd/main.jsonnet) y un módulo .libsonnet para el servidor siguiendo el patrón del repo (StatefulSet + Service + volumen hostPath en /data/minecraft)
- [ ] #2 El servidor usa la imagen itzg/minecraft-server:java25 con TYPE=PAPER (no vanilla), VERSION=26.2, heap 4G (MEMORY=4G) y USE_AIKAR_FLAGS=true
- [ ] #3 El StatefulSet define memoria request=limit=6Gi (QoS Guaranteed) y CPU request 1 sin limit; StatefulSet.metadata.name == spec.serviceName; terminationGracePeriodSeconds holgado (~90s)
- [ ] #4 El puerto 25565 (TCP) queda expuesto directamente por el Service de mc-router en modo LoadBalancer (sin Traefik), con el Service del server anotado (mc-router.itzg.me/defaultServer) y puerto llamado `minecraft`
- [ ] #5 El mundo persiste en NVMe (/data/minecraft), no en HDD
- [ ] #6 El tag de imagen (:java25), VERSION=26.2 y el build de Paper (PAPER_BUILD) quedan centralizados/pinneados en versions.json
- [ ] #7 Un cliente de Minecraft puede conectarse y jugar
- [ ] #8 mc-router está desplegado con -in-kube-cluster y el RBAC necesario para escalar el StatefulSet del servidor
- [ ] #9 Con el server a 0 réplicas, un intento de conexión lo escala a 1 (wake) y, tras el periodo de inactividad (down-after 1h), mc-router lo devuelve a 0 (sleep)
- [ ] #10 Existe un CronJob de K8s (itzg/mc-backup, one-shot, diario, uid 1000) que respalda /data/minecraft (RO) hacia el repo restic en /cold-data/minecraft (RW)
- [ ] #11 El backup usa el método restic con retención GFS nativa (PRUNE_RESTIC_RETENTION="--keep-daily 7 --keep-weekly 4 --keep-monthly 6") y limpieza automática de las caducadas; RESTIC_PASSWORD en SealedSecret
- [ ] #12 La consistencia del backup se garantiza vía el marcador .paused: preStop del STS hace touch /data/minecraft/.paused y el arranque lo borra, de modo que con el server dormido mc-backup snapshotea file-only y con el server encendido hace flush por RCON
- [ ] #13 El server corre con online-mode=true y OPS=Duning (ConfigMap), SIN whitelist (open-join asumido)
- [ ] #14 RCON habilitado con contraseña en SealedSecret (compartida con mc-backup) y puerto 25575 solo ClusterIP (nunca expuesto por el LoadBalancer)
- [ ] #15 mc-router usa un Role namespaced en `games` (no ClusterRole) y -kube-namespace=games: list/watch de services y statefulsets (inevitable para el auto-discovery, mitigado por ser ns dedicado solo-Minecraft) + get/update/patch sobre statefulsets y statefulsets/scale acotado con resourceNames al STS `minecraft`
- [ ] #16 El pod del server corre endurecido: runAsNonRoot (uid 1000), capabilities drop ALL, sin privileged, readOnlyRootFilesystem, seccomp RuntimeDefault, emptyDir en /tmp, montando solo el hostPath /data/minecraft
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Desplegar con /deploy
<!-- DOD:END -->
