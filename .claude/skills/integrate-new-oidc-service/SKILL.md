---
name: integrate-new-oidc-service
description: Integrate a new service with Authelia via OpenID Connect (OIDC). Use when the user wants to add SSO, OIDC login, or Authelia authentication to a new service.
---

# /integrate-new-oidc-service

Integrar un nuevo servicio con Authelia via OIDC. Sigue todos los pasos en orden.

El usuario debe haberte dicho el nombre del servicio que quiere integrar (p.ej. `synapse`, `grafana`, `gitea`). Si no lo ha dicho, pregúntalo antes de empezar.

## Paso 1 — Buscar la guía oficial de Authelia para el servicio

Usa el CLI de GitHub para buscar si existe una guía de integración OIDC para ese servicio:

```bash
gh api "repos/authelia/authelia/git/trees/master?recursive=1" \
  --jq '.tree[] | select(.path | test("integration/openid-connect/clients/<nombre-servicio>"; "i")) | .path'
```

Sustituye `<nombre-servicio>` por el nombre del servicio en minúsculas (p.ej. `synapse`, `grafana`).

**Si no se encuentra ningún resultado:** detente y reporta al usuario que Authelia no tiene una guía oficial para ese servicio. Muestra la lista completa de servicios soportados ejecutando:

```bash
gh api "repos/authelia/authelia/git/trees/master?recursive=1" \
  --jq '[.tree[] | select(.path | test("integration/openid-connect/clients/[^/]+/index.md")) | (.path | split("/")[5])] | sort | .[]'
```

Pregunta al usuario si quiere intentarlo con un nombre alternativo o proceder de forma manual.

**Si se encuentra la guía:** descárgala en el siguiente paso.

## Paso 2 — Descargar y leer la guía

```bash
gh api "repos/authelia/authelia/contents/docs/content/integration/openid-connect/clients/<nombre-servicio>/index.md" \
  --jq '.content' | base64 -d
```

Lee el contenido completo. Extrae y anota:

- **Todas** las `redirect_uris` que requiere el servicio — algunas apps tienen múltiples (p.ej. Immich tiene `/auth/login`, `/user-settings` y `app.immich:///oauth-callback` para la app móvil). Cópialas todas.
- El valor exacto de `token_endpoint_auth_method` — **no asumas `client_secret_basic`**, cada servicio especifica el suyo (`client_secret_post`, `client_secret_basic`, etc.).
- El formato de `issuer` / `issuerUrl` que espera el servicio — algunos quieren la URL base (`https://auth.domain.com`) y otros la URL de discovery completa (`https://auth.domain.com/.well-known/openid-configuration`).
- Los `scopes` necesarios.
- El bloque de configuración para Authelia (`configuration.yml`).
- El bloque de configuración para el servicio (`homeserver.yaml`, GUI, o el que corresponda).
- Cualquier restricción de `authorization_policy` o `attribute_requirements` que recomiende la guía.

## Paso 3 — Leer la guía de generación de credenciales

Lee la sección "How do I generate a client identifier or client secret?" del FAQ de OIDC de Authelia:

```bash
gh api "repos/authelia/authelia/contents/docs/content/integration/openid-connect/frequently-asked-questions.md" \
  --jq '.content' | base64 -d | sed -n '/### How do I generate a client identifier or client secret/,/^### /p'
```

Las reglas clave que debes aplicar:

1. **Client ID**: aleatorio, ≥ 40 caracteres, solo RFC3986 Unreserved Characters.
2. **Client Secret**: se genera en texto plano, se hashea con PBKDF2-SHA512. Authelia almacena el hash; el servicio usa el texto plano.
3. El ID y el secret deben ser únicos por cliente.

## Paso 4 — Generar el Client ID

> **Usa el pod de Authelia en el clúster (`kubectl exec`), NO `docker run authelia/authelia` local.** La doc oficial de Authelia muestra el flujo con Docker, pero aquí reutilizamos el binario del pod ya desplegado: garantiza que la **misma versión** de Authelia genera y consume las credenciales (evita desajustes de formato de hash entre versiones) y no requiere tener la imagen en local.

> **El `kubectl exec` contra el deploy de Authelia puede requerir aprobación del usuario** (el clasificador de permisos lo trata como acción contra un target compartido). Si se deniega, no es un error del comando: pide al usuario que lo apruebe o lo ejecute con el prefijo `!`.

> **Cuidado con la salida de `authelia crypto`:** NO imprime el valor crudo. `crypto rand` lo prefija con `Random Value: ` y `crypto hash generate` con `Digest: `. Además, si el deploy tiene init containers, `kubectl exec` escribe un warning `Defaulted container "authelia" out of: ...` en **stderr**. Por eso hay que **extraer el valor** (`tail -1 | sed 's/.*: //'`) y **quitar el newline final** (`tr -d '\n'`) antes de usarlo — un `> fichero` directo guardaría la etiqueta y/o el `\n`, corrompiendo el secreto al cifrarlo.

Genera el Client ID redirigiendo la salida (ya parseada) a un fichero temporal. **El valor no debe aparecer en el contexto de Claude.**

```bash
kubectl exec -n auth deploy/authelia -- authelia crypto rand --length 72 --charset rfc3986 \
  | tail -1 | sed 's/.*: //' | tr -d '\n' > /tmp/oidc_client_id.txt
# Sanity check sin exponer el valor:
echo "client_id chars: $(wc -c < /tmp/oidc_client_id.txt)"   # debe ser 72
```

El fichero `/tmp/oidc_client_id.txt` contiene el `client_id`. Se usará con `cat` en los pasos siguientes y se eliminará al final.

## Paso 5 — Generar y hashear el Client Secret

Genera el secret (texto plano) y su hash PBKDF2, redirigiendo cada valor a su propio fichero temporal. **Ningún valor debe aparecer en el contexto de Claude.**

```bash
# 1. Texto plano del secret (parseado y sin newline, igual que el Client ID)
kubectl exec -n auth deploy/authelia -- authelia crypto rand --length 72 --charset rfc3986 \
  | tail -1 | sed 's/.*: //' | tr -d '\n' > /tmp/oidc_secret_plain.txt

# 2. Hash PBKDF2 a partir del texto plano.
#    OJO: esta versión de Authelia NO tiene flag `--stdin`. Se usa `--password "$(cat ...)"`
#    (el valor lo expande el shell, así que no aparece en el contexto) + `--no-confirm`.
#    La salida trae `Digest: <hash>`; se extrae con grep/sed.
kubectl exec -i -n auth deploy/authelia -- \
  authelia crypto hash generate pbkdf2 --variant sha512 --no-confirm \
  --password "$(cat /tmp/oidc_secret_plain.txt)" \
  | grep -i 'digest' | sed -E 's/^Digest:[[:space:]]*//' | tr -d '\n' > /tmp/oidc_secret_hash.txt
# Sanity check sin exponer el valor:
echo "hash prefix: $(cut -c1-14 /tmp/oidc_secret_hash.txt)"   # debe ser $pbkdf2-sha512
```

- `/tmp/oidc_secret_plain.txt` → texto plano → se cifrará con kubeseal para el secreto del **servicio**
- `/tmp/oidc_secret_hash.txt` → hash `$pbkdf2-sha512$...` → va en la config de **Authelia** como `client_secret`

**Nunca hagas `cat` de estos ficheros para mostrar su contenido en el contexto.** Para validar usa `wc -c` (longitud) o `cut -c1-N` (prefijo no sensible), nunca el valor completo.

## Paso 6 — Producir los bloques de configuración finales

Usa `cat` sobre los ficheros temporales para leer los valores e inyectarlos en los bloques de configuración. **No imprimas los valores en el contexto de Claude; escríbelos directamente a los ficheros de destino.**

### Bloque Authelia

En este proyecto, el `client_id` y el hash del `client_secret` **nunca se hardcodean** en `authelia.config.yml`. Se almacenan en env vars que Authelia lee con `{{ env '...' }}`. El bloque que hay que añadir al fichero de clientes OIDC (`lib/auth/authelia/authelia.config.yml`) sigue este patrón:

```yaml
- client_id: '{{ env `IDENTITY_PROVIDERS_OIDC_CLIENTS_<NOMBRE>_CLIENT_ID` }}'
  client_name: '<Nombre Visible>'
  client_secret: '{{ env `IDENTITY_PROVIDERS_OIDC_CLIENTS_<NOMBRE>_CLIENT_SECRET_DIGEST` }}'
  public: false
  authorization_policy: 'two_factor'
  consent_mode: 'auto'
  require_pkce: false           # o true si lo indica la guía
  pkce_challenge_method: ''     # o 'S256' si lo indica la guía
  redirect_uris:
    # COPIAR TODAS las redirect URIs que liste la guía, incluyendo URIs de apps móviles
    - 'https://<dominio-servicio>/<redirect-path-1>'
    - 'https://<dominio-servicio>/<redirect-path-2>'   # si hay más
    - 'app.nombre:///oauth-callback'                   # si hay URI de app móvil
  scopes:
    - 'openid'
    - 'profile'
    - 'email'
    # añadir los scopes adicionales que indique la guía
  response_types:
    - 'code'
  grant_types:
    - 'authorization_code'
  access_token_signed_response_alg: 'none'
  userinfo_signed_response_alg: 'none'
  token_endpoint_auth_method: '<copiar de la guía: client_secret_post | client_secret_basic>'
```

Los valores reales de las env vars se añadirán al SealedSecret de Authelia en el Paso 7.

### Bloque del servicio

Replica el bloque de configuración de la guía. Las credenciales llegarán al pod vía SealedSecret como env vars — el servicio no las ve hardcodeadas. Configura el servicio para leerlas desde env vars si lo soporta, o inyéctala vía init container / config-merge si el servicio requiere un fichero de configuración estático.

## Paso 7 — Cifrar credenciales y añadir a los SealedSecrets

Hay que cifrar **cuatro valores** y distribuirlos en los secrets correctos:

| Valor | Destino |
|---|---|
| `client_id` | SealedSecret de **Authelia** + SealedSecret del **servicio** |
| `client_secret` (hash) | SealedSecret de **Authelia** |
| `client_secret` (texto plano) | SealedSecret del **servicio** |

> **Nombres de los SealedSecret:** el scope strict ata el valor cifrado a `namespace` + nombre del SealedSecret, así que tienen que ser **exactos**. Con el patrón `u.sealedSecret.forEnv(component, ...)` el nombre es `<nombre-del-deployment>-sealed-secret`. Para Authelia es `authelia-sealed-secret` (namespace `auth`). Verifica el nombre real en el `.libsonnet` antes de cifrar.

> **Quita el newline al cifrar.** `encrypt-secret.sh` cifra exactamente lo que recibe por stdin; si el fichero temporal tuviera un `\n` final acabaría dentro del secreto. Los ficheros del Paso 4/5 ya vienen sin newline, pero por seguridad pásalos con `tr -d '\n'`.

### 7a — Cifrar para el SealedSecret del servicio

El servicio necesita el `client_id` en texto plano y el `client_secret` en texto plano. Usa scope strict (namespace del servicio):

```bash
tr -d '\n' < /tmp/oidc_client_id.txt     | ./scripts/encrypt-secret.sh <namespace-servicio> <nombre-sealed-secret> > /tmp/sealed_svc_client_id.txt
tr -d '\n' < /tmp/oidc_secret_plain.txt  | ./scripts/encrypt-secret.sh <namespace-servicio> <nombre-sealed-secret> > /tmp/sealed_svc_client_secret.txt
```

### 7b — Cifrar para el SealedSecret de Authelia

Authelia necesita el `client_id` en texto plano y el `client_secret` en **hash**. Usa scope strict (namespace `auth`):

```bash
tr -d '\n' < /tmp/oidc_client_id.txt    | ./scripts/encrypt-secret.sh auth <nombre-sealed-secret-authelia> > /tmp/sealed_auth_client_id.txt
tr -d '\n' < /tmp/oidc_secret_hash.txt  | ./scripts/encrypt-secret.sh auth <nombre-sealed-secret-authelia> > /tmp/sealed_auth_client_hash.txt
```

### 7c — Inyectar los valores cifrados en los `.secrets.json` con `jq`

Los valores `AgC...` son largos y no deben editarse a mano (riesgo de romper el JSON). Usa `jq --rawfile` para leer cada fichero cifrado y asignarlo a su clave, escribiendo el resultado de vuelta al fichero. El `rtrimstr("\n")` quita el newline que `--rawfile` añade. Los valores cifrados son seguros de manejar, pero esta técnica además evita pegarlos en el contexto:

```bash
# Secrets del servicio (claves de env var que consume el servicio, p.ej. OIDC_CLIENT_ID/OIDC_CLIENT_SECRET)
jq --rawfile cid /tmp/sealed_svc_client_id.txt --rawfile csec /tmp/sealed_svc_client_secret.txt \
  '.<servicio>.OIDC_CLIENT_ID = ($cid|rtrimstr("\n")) | .<servicio>.OIDC_CLIENT_SECRET = ($csec|rtrimstr("\n"))' \
  lib/<categoria>/<servicio>/<servicio>.secrets.json > /tmp/svc.new \
  && mv /tmp/svc.new lib/<categoria>/<servicio>/<servicio>.secrets.json

# Secrets de Authelia (claves de env var IDENTITY_PROVIDERS_OIDC_CLIENTS_<NOMBRE>_*)
jq --rawfile cid /tmp/sealed_auth_client_id.txt --rawfile chash /tmp/sealed_auth_client_hash.txt \
  '.authelia.IDENTITY_PROVIDERS_OIDC_CLIENTS_<NOMBRE>_CLIENT_ID = ($cid|rtrimstr("\n"))
   | .authelia.IDENTITY_PROVIDERS_OIDC_CLIENTS_<NOMBRE>_CLIENT_SECRET_DIGEST = ($chash|rtrimstr("\n"))' \
  lib/auth/authelia/authelia.secrets.json > /tmp/auth.new \
  && mv /tmp/auth.new lib/auth/authelia/authelia.secrets.json
```

### 7d — Verificar el render (sin exponer secretos)

Compila ambos entornos y comprueba con `jq` que las claves cifradas aparecen en los SealedSecret renderizados. Esto valida tanto el Jsonnet como el cableado de las claves:

```bash
tk eval environments/auth >/dev/null && tk eval environments/<categoria> >/dev/null && echo "eval OK"

# Claves del SealedSecret del servicio:
tk eval environments/<categoria> | jq -r '.. | objects
  | select(.kind=="SealedSecret" and .metadata.name=="<nombre-sealed-secret>")
  | .spec.encryptedData | keys[]'

# Claves del cliente en el SealedSecret de Authelia:
tk eval environments/auth | jq -r '.. | objects
  | select(.kind=="SealedSecret" and .metadata.name=="authelia-sealed-secret")
  | .spec.encryptedData | keys[] | select(test("<NOMBRE>"))'
```

## Paso 8 — Limpiar ficheros temporales

Una vez que todos los valores estén en sus destinos (`.secrets.json` del servicio y `authelia.secrets.json`), elimina **todos** los ficheros temporales:

```bash
rm -f /tmp/oidc_client_id.txt /tmp/oidc_secret_plain.txt /tmp/oidc_secret_hash.txt \
      /tmp/sealed_svc_client_id.txt /tmp/sealed_svc_client_secret.txt \
      /tmp/sealed_auth_client_id.txt /tmp/sealed_auth_client_hash.txt
```

**Este paso es obligatorio.** No des la integración por finalizada sin haberlos borrado.

## Notas importantes

- **Las contraseñas y secrets nunca deben aparecer en el contexto de Claude.** Siempre redirige a fichero y usa `cat`/`jq --rawfile` para inyectar. Para validar usa `wc -c` o `cut -c1-N`, nunca el valor completo.
- **Genera los secretos con el pod del clúster (`kubectl exec deploy/authelia`), no con `docker run` local** — misma versión que los consume, sin imagen local.
- **El `kubectl exec` puede requerir aprobación del usuario** (target compartido). Si se deniega, pide aprobación; no es un fallo del comando.
- **La salida de `authelia crypto` no es cruda:** trae `Random Value:` / `Digest:` y un warning `Defaulted container ...` en stderr. Extrae el valor (`tail -1 | sed 's/.*: //'` o `grep -i digest | sed ...`) y haz `tr -d '\n'` antes de usarlo o cifrarlo.
- **`authelia crypto hash generate pbkdf2` no tiene `--stdin`** en la versión desplegada: usa `--no-confirm --password "$(cat fichero)"` (el shell expande el valor, no entra en el contexto).
- **Quita el `\n` (`tr -d '\n'`) antes de `encrypt-secret.sh`** — cifra exactamente lo que recibe; un newline residual corrompe el secreto.
- **Inyecta los valores cifrados con `jq --rawfile ... rtrimstr("\n")`**, no a mano, para no romper el JSON ni pegar valores en el contexto.
- **Verifica con `tk eval | jq`** que las claves cifradas aparecen en los SealedSecret renderizados antes de dar por terminada la integración.
- **Borra todos los ficheros temporales** al terminar. Si el proceso se interrumpe, asegúrate de limpiarlos antes de salir.
- En Authelia se almacena el **hash** del secret; en el servicio se usa el **texto plano** (que llega al pod vía SealedSecret como env var).
- El `client_id` y el `client_secret` **nunca se hardcodean** en `authelia.config.yml` — se referencian con `{{ env '...' }}` y sus valores van en el SealedSecret de Authelia.
- **`token_endpoint_auth_method`**: copia siempre el valor que indique la guía del servicio (`client_secret_post` o `client_secret_basic`). No asumas ninguno por defecto.
- **Redirect URIs**: copia **todas** las que liste la guía. Los clientes móviles añaden URIs con esquemas propios (`app.nombre:///...`).
- **Formato del issuer**: comprueba si el servicio espera la URL base o la URL completa de discovery (`/.well-known/openid-configuration`). La guía lo especifica.
- **`consent_mode: 'auto'`**: añádelo siempre al bloque de Authelia para evitar que se re-pida consentimiento en cada login.
- Si la guía menciona `pkce_challenge_method: 'S256'`, actívalo en Authelia y asegúrate de que el servicio también lo soporta.
- Si la guía menciona `attribute_requirements` (grupos), verifica que el grupo exista en Authelia antes de aplicarlo.
