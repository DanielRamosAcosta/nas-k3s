---
title: "Dar de alta exporters de metricas faltantes"
status: Done
priority: 2
labels: [monitoring, observability, exporters]
parent:
references: []
created_date: 2026-10-16 19:15
---

## Description

## 📌 TLDR

Desplegar 5 exporters de Prometheus para tapar los agujeros ciegos de observabilidad: las 4 bases de datos (Postgres, MariaDB, Valkey, CouchDB) no exportan ninguna métrica, y no hay monitorización de expiración de certificados ni de uptime externo. El exporter de Postgres además dará la frescura de los backups vía SQL.

## 🎯 Contexto funcional

Hoy la monitorización de hardware es muy completa, pero las capas de **datos** y **continuidad/red** están ciegas:

- **Bases de datos**: Postgres es la columna vertebral (immich, authelia, synapse, wger, seerr…) y no se mide nada. Cuando una app se degrade no sabremos si la causa es la BD (conexiones agotadas, locks, tamaño, cache hit).
- **Certificados TLS**: wildcard Let's Encrypt vía ACME DNS-01. Si la renovación falla, nos enteramos cuando caduca.
- **Uptime externo**: "Pod Ready" no garantiza que la URL responda 200 por fuera.
- **Conectividad internet/DNS**: relevante por el historial de bloqueos del ISP (LaLiga/SNI-DPI).

## ⚙️ Contexto técnico

Todos como `Deployment` en el namespace `monitoring`, siguiendo el patrón existente (`lib/monitoring/<app>/<app>.libsonnet` + anotaciones `prometheus.io/scrape`). Cada exporter de BD necesita un usuario/rol de solo-lectura o monitoring y su SealedSecret.

| Exporter | Imagen | Puerto | Credencial necesaria |
|---|---|---|---|
| postgres_exporter | `quay.io/prometheuscommunity/postgres-exporter` | 9187 | Rol `monitoring` en Postgres + DSN sellado |
| mysqld_exporter | `prom/mysqld-exporter` | 9104 | Usuario con `PROCESS, REPLICATION CLIENT, SELECT` en MariaDB |
| redis_exporter | `oliver006/redis_exporter` | 9121 | `REDIS_ADDR` de Valkey (+ password si aplica) |
| couchdb-exporter | `gesellix/couchdb-prometheus-exporter` | 9984 | Basic-auth de CouchDB |
| blackbox_exporter | `prom/blackbox-exporter` | 9115 | Ninguna; scrape config con lista de targets (IngressRoutes públicos + dominios clave del ISP) |

Notas:
- **blackbox tapa 3 huecos a la vez**: expiración de certs (`probe_ssl_earliest_cert_expiry`), uptime externo (`probe_success` / `probe_http_status_code`) y conectividad internet/DNS (módulos `dns`/`tcp`).
- **postgres_exporter** admite *custom queries* SQL → aprovechar para exponer tamaño por base de datos y **frescura del último backup** (consultando una tabla/marcador escrito por el cronjob de dump).
- Añadir versiones a `environments/versions.json` y registrar las apps en el `main.jsonnet` del entorno `monitoring` con `u.labelApp()`.
- Las reglas de alerta nuevas (Postgres caído, certs <14d, backup obsoleto, uptime externo) se tratan en una tarea aparte.

## Acceptance Criteria

- [x] #1 postgres_exporter desplegado, scrapeado (`pg_up == 1`) y con custom queries para tamaño por BD y frescura de backup
- [x] #2 mysqld_exporter desplegado y scrapeado (`mysql_up == 1`)
- [x] #3 redis_exporter desplegado y scrapeado contra Valkey (`redis_up == 1`)
- [x] #4 couchdb-exporter desplegado y scrapeado
- [x] #5 blackbox_exporter desplegado con módulos `http`/`dns` para **detección de bloqueos del ISP/DNS** (vantage del NAS), con lista curada de dominios clave (`api.radarr.video`, rango Cloudflare, control sano, DoH 1.1.1.1). El uptime externo y la caducidad de certificados quedan fuera: ya los cubre Grafana Cloud Synthetic Monitoring desde un vantage externo.
- [x] #6 Credenciales de monitoring de cada BD creadas como usuarios de solo-lectura/monitoring y selladas (SealedSecret), sin exponer secretos en el contexto. **Excepción CouchDB**: no existe rol readonly para `/_node/_stats` → se reusa el admin principal existente (ya sellado).

## Decisiones de diseño

> Decisiones tomadas en la ronda de grill (16-10-2026). Aún **no** es el plan paso a paso.

### Ejecución
- Un ticket paraguas; **un subagente por exporter, e2e 100% autónomo, en serie**. Cada subagente no termina hasta ver la métrica viva en VictoriaMetrics con **evidencia** (query + valor en su informe). Arranca con contexto limpio para no contaminar el contexto global.
- Orden por esfuerzo/valor: blackbox → redis → couchdb → mariadb → postgres.
- **Namespaces**: los exporters de BD (postgres, mysqld, couchdb, redis) corren en **`databases`** junto a su BD (localidad de credenciales — evita re-sellar cross-namespace); **blackbox** en `monitoring`. El scrape por anotaciones `prometheus.io/*` los recoge en cualquier namespace.
- **Ficheros**: `lib/databases/<db>/<db>-exporter.libsonnet` + su `.secrets.json` al lado de la BD; blackbox en `lib/monitoring/blackbox/`. Versiones en `lib/versions.json`; registro en el `main.jsonnet` del entorno correspondiente (`databases` o `monitoring`) con `u.labelApp()`.

### Definición de "done con evidencia" por exporter
El subagente consulta VictoriaMetrics vía el MCP `grafanaSelfHosted` (`query_prometheus`) y obtiene resultado no vacío:

| Exporter | Señal `up` | Señal de contenido |
|---|---|---|
| postgres | `pg_up == 1` | `pg_database_size_bytes` (una serie por BD) + métrica de frescura de backup con timestamp reciente |
| mysqld | `mysql_up == 1` | `mysql_global_status_uptime > 0` |
| redis | `redis_up == 1` | `redis_connected_clients` presente |
| couchdb | equivalente `up` | nº de databases > 0 |
| blackbox | `probe_success` por target | `probe_http_status_code` / `probe_duration_seconds` por target |

### Postgres (el más complejo)
- Rol `monitoring` vía **script nuevo** `postgres.create-monitoring-user.sh` (Job), minimalista: `CREATE ROLE monitoring LOGIN` + `GRANT pg_monitor`. No reusar `create-user.sh` (crearía BD basura y revocaría cosas no deseadas).
- BD **`monitoring` dedicada** (owner el rol `monitoring`); el exporter conecta **ahí con una sola conexión**.
- Tamaño por BD vía **custom query** `SELECT datname, pg_database_size(datname) FROM pg_database` (descubrimiento dinámico, cero mantenimiento al añadir apps). Se descarta `--auto-discover-databases` (obligaría a `GRANT CONNECT` BD por BD).
- Frescura de backup vía **tabla marcador** `backup_log` en la BD `monitoring`: el script de migración la crea y `postgres.dump.sh` hace **UPSERT por BD** al terminar cada dump. Custom query lee `max(finished_at)` por BD.
- Credencial: solo el password sale del SealedSecret (`DATA_SOURCE_PASS`); host/puerto/BD/usuario en ConfigMap (`DATA_SOURCE_URI`, `DATA_SOURCE_USER`).

### MariaDB
- Usuario `monitoring` vía **script nuevo** `mariadb.create-monitoring-user.sh` (Job): `GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.*`.
- `mysqld-exporter` v0.20.0 → `.my.cnf` montado como **fichero sellado** (`u.sealedSecret.forFile` + `--config.my-cnf`), no DSN por env.

### CouchDB
- **Reusa el admin principal** existente (sellado strict en `databases`, ya local → sin re-sellar). Motivo: `/_node/_stats` requiere server admin; CouchDB no ofrece readonly granular. Un segundo admin dedicado no persiste de forma limpia (el entrypoint solo re-siembra un admin; el `local.ini` runtime no se guarda en el hostPath). Es read-only de facto (solo GETs de stats).

### Redis / Valkey
- Trivial: Valkey **sin auth**. `REDIS_ADDR=valkey.databases.svc.cluster.local:6379`, sin password ni SealedSecret.

### Blackbox (re-scopeado)
- **Solo detección de bloqueos del ISP/DNS** — único valor que no se cubre desde fuera (vantage del NAS: "¿qué alcanza la red de casa?", caso LaLiga/SNI-DPI).
- **Fuera**: uptime externo (dead-man's-switch: si cae el internet de casa cae el prober) y caducidad de cert (wildcard → un único check HTTPS basta) → **ya cubiertos por Grafana Cloud Synthetic Monitoring** desde PoPs externos.
- Módulos `http_2xx` + `dns` contra **lista curada a mano** (static_configs en VM): `api.radarr.video`, un dominio tras rango Cloudflare (`188.114.96.0/24`), un control sano para distinguir bloqueo selectivo de caída total, y DoH 1.1.1.1. Mide el bloqueo (`probe_success=0`), no lo esquiva. Correlación con la API `hayahora.futbol` = mejora futura.

### Secretos
- Sellado **strict en `databases`** para postgres y mariadb (Job de creación y exporter comparten namespace). Generación vía fichero temporal (`openssl ... > /tmp/pw.txt` → `encrypt-secret.sh` → `rm`), nunca por el contexto.

### Fuera de scope (tareas aparte)
- Reglas de **alertas** (Postgres caído, cert <14d, backup obsoleto, uptime).
- **Dashboards** de Grafana.

## Implementation Plan

> **Cada fase = un exporter, e2e, por un subagente autónomo, en serie.** El subagente arranca con contexto limpio, implementa, **despliega** vía GitOps y **no termina hasta adjuntar evidencia** de la métrica viva en VictoriaMetrics. Se pasa a la siguiente fase solo cuando la anterior está verde.
>
> **Ejecución secuencial estricta:** implementar una fase → **parar** → desplegar esa fase → verificar su checkpoint → solo entonces la siguiente. No adelantar código de fases posteriores ni colapsar despliegues. Las fases complejas (4 y 5) tienen **despliegues intermedios** propios: la migración/credencial se despliega y verifica **antes** de desplegar el exporter.
>
> **Despliegue** = skill `/deploy` (crea PR, espera CI, squash-merge a `main`, espera rollout de ArgoCD). Esperar a que cada `/deploy` termine su rollout antes del siguiente evita la carrera de la rama `manifests`.
>
> **Verificación** = MCP `grafanaSelfHosted` → `query_prometheus` contra VictoriaMetrics. Obtener primero el `uid` del datasource de VM con `list_datasources` tipo `prometheus`. El scrape corre cada 30s; tras el rollout dar ~1 min antes de consultar.
>
> **Prerrequisito (todas las fases que sellan/crean credencial):** túnel SSH al clúster activo para `kubeseal`/`kubectl` (`ssh -fN -L 6443:localhost:6443 nas`; si el DDNS está caído, `ssh nas-tunnel`).
>
> Patrón de referencia de un exporter existente: `lib/monitoring/deluge-exporter/deluge-exporter.libsonnet` (Deployment + ConfigMap env + `Service` con `u.metrics(port)` + SealedSecret). Antes de fijar la versión de cada imagen, buscar el último tag estable con `skopeo list-tags docker://<imagen>`.

---

### Fase 1 — blackbox (namespace `monitoring`, sin credenciales)

Detección de bloqueos del ISP/DNS. **Matiz clave:** el scrape de blackbox NO es por anotación `prometheus.io/scrape` (eso scrapearía las métricas internas del propio exporter, no las sondas). Las sondas se obtienen con un **job multi-target** en VM que apunta a `/probe?target=…&module=…`.

1. Añadir versión a `lib/versions.json`: `blackboxExporter` → `quay.io/prometheus/blackbox-exporter` (último tag estable vía `skopeo`).
2. Crear `lib/monitoring/blackbox/blackbox.config.yml` (importstr): módulos `http_2xx` (sin seguir redirects, `fail_if_not_ssl: false`, acepta cualquier 2xx; un RST/timeout → `probe_success=0`) y `dns` (query A contra el resolver, p. ej. consultar `cloudflare.com` vía `1.1.1.1`).
3. Crear `lib/monitoring/blackbox/blackbox.libsonnet`: Deployment `blackbox-exporter` (:9115) montando el ConfigMap en `/etc/blackbox_exporter/config.yml` + `Service` ClusterIP (sin anotación de scrape de probe).
4. Añadir el **job `blackbox`** en `lib/monitoring/victoriametrics/victoriametrics.yml`. **No copiar el job `nut-salicru` como molde de relabels**: nut es un target único sin `relabel_configs`, no demuestra el baile multi-target. Escribir desde cero: `metrics_path: /probe`, `params.module: [http_2xx]`, `static_configs.targets` con la lista curada, y los `relabel_configs` estándar del blackbox: `__address__`→`__param_target`, luego `__param_target`→`instance`, y finalmente `__address__`=`blackbox-exporter.monitoring.svc.cluster.local:9115`. El módulo `dns` va en un job aparte (distinto `params.module`).
5. Targets curados: `api.radarr.video` (caso LaLiga), un dominio tras rango Cloudflare `188.114.96.0/24`, un **control sano** (dominio que nunca se bloquea) para distinguir bloqueo selectivo de caída total, y `1.1.1.1` (módulo dns, secuestro DoH).
6. Registrar `blackbox.new()` en el bloque `exporters` de `environments/monitoring/main.jsonnet`.
7. **Desplegar** con la skill `/deploy`.
8. **Checkpoint**: en VM, `probe_success` devuelve una serie por target, y `probe_http_status_code` / `probe_duration_seconds` tienen valor. El control sano debe dar `probe_success=1`. Adjuntar query + valores.

---

### Fase 2 — redis/valkey (namespace `databases`, sin credenciales)

1. Añadir versión a `lib/versions.json`: `redisExporter` → `docker.io/oliver006/redis_exporter` (último tag estable vía `skopeo`).
2. Crear `lib/databases/valkey/valkey-exporter.libsonnet`: Deployment `redis_exporter` (:9121) con `REDIS_ADDR=redis://valkey.databases.svc.cluster.local:6379` por ConfigMap (Valkey **sin auth**) + `Service` + `u.metrics('9121')`.
3. Registrar `valkey.new()`-style exporter en `environments/databases/main.jsonnet` (como entrada propia del Environment, con `u.labelApp()`).
4. **Desplegar** con la skill `/deploy`.
5. **Checkpoint**: en VM, `redis_up == 1` y `redis_connected_clients` presente. Adjuntar query + valores.

---

### Fase 3 — couchdb (namespace `databases`, reusa admin)

1. Añadir versión a `lib/versions.json`: `couchdbExporter` → `docker.io/gesellix/couchdb-prometheus-exporter` (último tag estable vía `skopeo`).
2. Resolver las env/flags exactas del exporter (doc de la imagen vía Context7): el exporter gesellix espera `COUCHDB_USERNAME`/`COUCHDB_PASSWORD` (o flags `--couchdb.username`/`--couchdb.password`/`--couchdb.uri`), **no** `COUCHDB_USER`. Las claves del SealedSecret `couchdb` **existente** son `COUCHDB_USER`/`COUCHDB_PASSWORD`. ⚠️ `u.envVars.fromSealedSecret` **no renombra** (usa la key literal), así que NO sirve para esto: construir el envVar a mano con `envVar.fromSecretRef('COUCHDB_USERNAME', 'couchdb-sealed-secret', 'COUCHDB_USER')` (el Secret real es `couchdb-sealed-secret`; `COUCHDB_PASSWORD` directo). **No se sella nada nuevo.**
3. Crear `lib/databases/couchdb/couchdb-exporter.libsonnet`: Deployment (:9984) apuntando a `http://couchdb.databases.svc.cluster.local:5984` + `Service` + `u.metrics('9984')`.
4. Registrar en `environments/databases/main.jsonnet`.
5. **Desplegar** con la skill `/deploy`.
6. **Checkpoint**: en VM, métrica `up` del exporter a 1 y nº de databases > 0 (p. ej. `couchdb_server_databases` o equivalente del exporter). Adjuntar query + valores.

---

### Fase 4 — mariadb (namespace `databases`, usuario nuevo + exporter)

Dos despliegues intermedios: primero la credencial de monitoring, luego el exporter.

**4A — Usuario de monitoring**
1. Crear `lib/databases/mariadb/mariadb.create-monitoring-user.sh` (patrón de `mariadb.create-user.sh`): `CREATE USER IF NOT EXISTS 'monitoring'@'%' IDENTIFIED BY …; GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'monitoring'@'%';`.
2. Generar password sin exponerlo: `openssl rand -base64 24 > /tmp/mon.txt`; `cat /tmp/mon.txt | ./scripts/encrypt-secret.sh databases mariadb-monitoring-sealed-secret`; `rm -f /tmp/mon.txt`. (El Job de creación lee la password del SealedSecret, no de un literal.)
3. Añadir el Job de migración + su ConfigMap al `mariadb.libsonnet` (o fichero contiguo), referenciando el SealedSecret. Registrar si hiciera falta.
4. **Desplegar** con la skill `/deploy`.
5. **Checkpoint 4A**: el Job `mariadb-create-monitoring-user` llega a `Completed` (sus logs en Loki, `{namespace="databases", pod=~"mariadb-create-monitoring-user.*"}`, sin error de GRANT).

**4B — Exporter**
6. Añadir versión a `lib/versions.json`: `mysqldExporter` → `quay.io/prometheus/mysqld-exporter` v0.20.0 (confirmar último estable vía `skopeo`; `quay.io/prometheus` por consistencia con `node-exporter`).
7. Credencial vía **`.my.cnf` sellado como fichero** (vía robusta en v0.20; el DSN-por-env `DATA_SOURCE_NAME` fue **eliminado**, no usarlo): construir `[client]\nhost=…\nuser=monitoring\npassword=…` en `/tmp/mycnf.txt`, `cat /tmp/mycnf.txt | ./scripts/encrypt-secret.sh databases mariadb-monitoring-mycnf` → montar con `u.sealedSecret.forFile` + `u.volumeMount.fromSealedSecretFile`; `rm -f /tmp/mycnf.txt`.
8. Crear `lib/databases/mariadb/mariadb-exporter.libsonnet`: Deployment `mysqld-exporter` (:9104) con `--config.my-cnf=<ruta montada>` + `Service` + `u.metrics('9104')`. Registrar en `environments/databases/main.jsonnet`.
9. **Desplegar** con la skill `/deploy`.
10. **Checkpoint 4B**: en VM, `mysql_up == 1` y `mysql_global_status_uptime > 0`. Adjuntar query + valores.

---

### Fase 5 — postgres (namespace `databases`, el más complejo — 3 despliegues intermedios)

**5A — Rol monitoring + BD `monitoring` + tabla `backup_log`**
1. Crear `lib/databases/postgres/postgres.create-monitoring-user.sh`: `CREATE ROLE monitoring LOGIN PASSWORD …` (idempotente, patrón `DO $$ … $$`), `GRANT pg_monitor TO monitoring`, `CREATE DATABASE monitoring OWNER monitoring` (si no existe). La tabla y su GRANT requieren **reconectar con `-d monitoring`** (patrón de `postgres.create-user.sh:63`, que reconecta con `-d "$USER_NAME"` para las extensiones): `CREATE TABLE IF NOT EXISTS public.backup_log(db text PRIMARY KEY, finished_at timestamptz NOT NULL)` + `GRANT SELECT ON public.backup_log TO monitoring`.
2. Generar password: `openssl rand -base64 24 > /tmp/pg.txt`; `cat /tmp/pg.txt | ./scripts/encrypt-secret.sh databases postgres-monitoring-sealed-secret`; `rm -f /tmp/pg.txt`.
3. Añadir el Job de migración (patrón `createUser`) + ConfigMap del script al `postgres.libsonnet`, referenciando el SealedSecret del rol y el admin (`POSTGRES_PASSWORD`) como ya hacen los demás Jobs.
4. **Desplegar** con la skill `/deploy`.
5. **Checkpoint 5A**: el Job `postgres-create-monitoring-user` llega a `Completed` (logs en Loki sin error); rol `monitoring`, BD `monitoring` y tabla `backup_log` creados.

**5B — UPSERT de frescura en el dump**
6. Modificar `lib/databases/postgres/postgres.dump.sh`: tras el `mv "$tmp" "$final"` exitoso de cada BD, hacer el UPSERT en `backup_log` (usa el `PGPASSWORD` admin del cronjob ya presente). ⚠️ **El script tiene `set -euo pipefail`: el UPSERT DEBE ir con guard** para que un fallo del marcador (BD `monitoring` no lista, etc.) **no aborte el backup real de las demás BD**:
   ```bash
   psql -h "$PGHOST" -p "$PGPORT" -U postgres -d monitoring -v ON_ERROR_STOP=1 \
     -c "INSERT INTO backup_log(db, finished_at) VALUES ('$db', now()) ON CONFLICT (db) DO UPDATE SET finished_at = EXCLUDED.finished_at;" \
     || echo "WARN: backup_log upsert falló para $db (backup OK, marcador no actualizado)"
   ```
   Nota: la propia BD `monitoring` entra en el bucle de dump (descubrimiento dinámico) → tendrá su fila en `backup_log` y aparecerá en `pg_database_size`. Esperado, no es bug.
7. **Desplegar** con la skill `/deploy`.
8. **Checkpoint 5B**: lanzar un dump ad-hoc `kubectl create job --from=cronjob/postgres-logical-dump postgres-dump-manual -n databases`; al terminar, `backup_log` tiene una fila por BD con `finished_at` reciente (verificar vía logs del job / una consulta puntual).

**5C — Exporter + custom queries**
9. Añadir versión a `lib/versions.json`: `postgresExporter` → `quay.io/prometheuscommunity/postgres-exporter` (último estable vía `skopeo`).
10. ⚠️ **Punto de mayor riesgo técnico — verificar formato ANTES de escribir**: el formato de custom-queries de `postgres-exporter` cambió entre versiones (`--extend.query-path` clásico vs collectors `--collector.custom_query` / `PG_EXPORTER_EXTEND_QUERY_PATH`). Consultar la doc de la versión exacta que fije `skopeo` (vía Context7) para el flag y formato correctos antes de redactar el YAML. Crear `lib/databases/postgres/postgres-queries.yml` (importstr) con: query de tamaño por BD (`SELECT datname AS db, pg_database_size(datname) AS bytes FROM pg_database WHERE NOT datistemplate`) y query de frescura (`SELECT db, extract(epoch FROM finished_at) AS last_backup_epoch FROM backup_log`).
11. Crear `lib/databases/postgres/postgres-exporter.libsonnet`: Deployment (:9187) con `DATA_SOURCE_URI=postgres.databases.svc.cluster.local:5432/monitoring?sslmode=disable` + `DATA_SOURCE_USER=monitoring` por ConfigMap y `DATA_SOURCE_PASS` por SealedSecret; montar `postgres-queries.yml` y pasar el flag de custom-queries correspondiente. `Service` + `u.metrics('9187')`. Registrar en `environments/databases/main.jsonnet`.
12. **Desplegar** con la skill `/deploy`.
13. **Checkpoint 5C**: en VM, `pg_up == 1`, la métrica de tamaño por BD con una serie por base de datos, y la métrica de frescura de backup con timestamp reciente. Adjuntar query + valores.

## Implementation Notes

Las 5 fases implementadas e2e por subagentes autónomos en serie (blackbox → redis → couchdb → mariadb → postgres), cada una desplegada vía `/deploy` y verificada con métrica viva en VictoriaMetrics (datasource `P4169E866C3094E38`).

**Fase 1 — blackbox** (PRs #292, #293). Namespace `monitoring`. Dos jobs multi-target en VM (`blackbox-http`, `blackbox-dns`). El módulo HTTP se corrigió de `http_2xx` a `http_reachable` con `valid_status_codes` amplio: para detección de bloqueos ISP la semántica correcta es *reachability* (éxito = cualquier respuesta HTTP; fallo = RST/timeout), si no `api.radarr.video`/`whisparr.servarr.com` daban `probe_success=0` por 404 estando alcanzables. Evidencia: `probe_success` por target (control sano=1, `1.1.1.1:53`=0 → secuestro DoH detectado).

**Fase 2 — redis/valkey** (PR #294). Namespace `databases`, sin auth (Valkey sin password, sin SealedSecret). Evidencia: `redis_up=1`, `redis_connected_clients`.

**Fase 3 — couchdb** (PR #295). Namespace `databases`, reusa el admin existente `couchdb-sealed-secret` (sin sellar nada nuevo). Env mapeada a mano (`COUCHDB_USERNAME`←key `COUCHDB_USER`) porque el exporter gesellix no usa `COUCHDB_USER`. Desviación: `TELEMETRY_ADDRESS=:9984` (el default `localhost:9984` dejaba el target inalcanzable). Evidencia: `couchdb_httpd_up=1`, `couchdb_httpd_databases_total=3`.

**Fase 4 — mariadb** (PRs #296, #297, #298). Usuario `monitoring` (`PROCESS, REPLICATION CLIENT, SELECT`) vía Job; credencial del exporter como `.my.cnf` sellado como fichero (v0.20 eliminó el DSN-por-env). SealedSecrets: `mariadb-monitoring-sealed-secret` (Job) y `my-cnf-sealed-secret` (exporter), ambos derivados de la misma password en un paso sin exponerla. Fix #298: `.my.cnf` a 0644 (el exporter non-root no podía leer el 0600 propiedad de root). Log benigno de `slave_status` (`REPLICATION CLIENT` → MariaDB lo renombró a `SLAVE MONITOR`; irrelevante en standalone). Evidencia: `mysql_up=1`, `mysql_global_status_uptime>0`.

**Fase 5 — postgres** (PRs #299, #301, #302, #303). Rol `monitoring` + `GRANT pg_monitor`, BD `monitoring` dedicada, tabla marcador `backup_log`. UPSERT por BD en `postgres.dump.sh` (con guard para no abortar el backup real). Exporter con `--extend.query-path` (v0.20.1). Fix #303: la custom query de tamaño colisionaba con el built-in `pg_database_size_bytes` y tiraba todo `/metrics` con HTTP 500 → se eliminó, el tamaño por BD lo da el colector built-in. Evidencia: `pg_up=1`, `pg_database_size_bytes` (15 series), `pg_backup_last_backup_epoch` (una serie por BD con epoch reciente tras un dump real).

Fuera de scope (tareas aparte): reglas de alertas y dashboards de Grafana.

### Fase 5 — postgres (completada)

**Imagen**: `quay.io/prometheuscommunity/postgres-exporter:v0.20.1` (último estable vía skopeo).

**Custom queries**: flag/env `PG_EXPORTER_EXTEND_QUERY_PATH` (equivale a `--extend.query-path`), formato clásico `queries.yaml` (deprecado pero vigente en v0.20.1, confirmado vía Context7). El nombre final de la métrica es `<clave_top_level>_<columna>`; columnas `LABEL` → etiquetas, `GAUGE` → valor.

**Desviación del plan (importante)**: la custom query de tamaño por BD se **eliminó**. El colector *built-in* del exporter ya emite `pg_database_size_bytes{datname}`; duplicarlo con una custom query de mismo nombre pero distinto help string provoca una colisión en el registro Prometheus → `/metrics` devuelve HTTP 500 y `up=0` (diagnosticado con `curl` a `/metrics`: "collected metric pg_database_size_bytes ... has help X but should have Y"). Se dejó solo la query de frescura `pg_backup_last_backup_epoch` (sin equivalente built-in). El tamaño por BD lo cubre el built-in — mismo nombre, misma semántica, una serie por BD.

**Ficheros**:
- `lib/databases/postgres/postgres.create-monitoring-user.sh` (nuevo) — Job 5A: rol `monitoring` (`GRANT pg_monitor`), BBDD `monitoring`, tabla `backup_log`.
- `lib/databases/postgres/postgres.dump.sh` (modificado) — 5B: UPSERT por BBDD en `backup_log` tras cada dump, con guard `||` (set -euo pipefail no debe abortar el backup real).
- `lib/databases/postgres/postgres-queries.yml` (nuevo) — 5C: solo `pg_backup` (frescura).
- `lib/databases/postgres/postgres-exporter.libsonnet` (nuevo) — 5C: Deployment :9187 + Service + `u.metrics('9187')`.
- `lib/databases/postgres/postgres.libsonnet` (modificado) — Job + ConfigMap + SealedSecret del rol monitoring.
- `lib/databases/postgres/postgres.secrets.json` — sellados strict: `monitoring.USER_PASSWORD` y `monitoringExporter.DATA_SOURCE_PASS` (misma password, dos nombres por el scope strict).
- `lib/versions.json`, `environments/databases/main.jsonnet` (registro).

**SealedSecrets**: `postgres-monitoring-sealed-secret` (key `USER_PASSWORD`, Job) y `postgres-exporter-sealed-secret` (key `DATA_SOURCE_PASS`, exporter). Ambos strict en `databases`, misma password generada vía `/tmp` → `encrypt-secret.sh` → `rm` (nunca expuesta).

**PRs**: #299 (5A), #301 (5B), #302 (5C) + #303 (fix colisión). Todos merge + rollout OK.

**Evidencia en VictoriaMetrics** (datasource `P4169E866C3094E38`):
- `pg_up{app="postgres-exporter"}` → `1`
- `pg_database_size_bytes` → una serie por BBDD (immich 3.03 GB, synapse 470 MB, wger 289 MB, … 16 series)
- `pg_backup_last_backup_epoch` → una serie por BBDD, epoch ~1792179918 (dump de hoy 2026-10-16), incluida la propia BBDD `monitoring`.
