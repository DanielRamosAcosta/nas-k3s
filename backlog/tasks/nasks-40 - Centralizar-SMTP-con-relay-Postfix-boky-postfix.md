---
id: NASKS-40
title: Centralizar SMTP con relay Postfix (boky/postfix)
status: Done
assignee: []
created_date: '2026-03-20 19:05'
updated_date: '2026-03-21 09:40'
labels:
  - infrastructure
  - smtp
  - refined
dependencies: []
references:
  - 'https://github.com/bokysan/docker-postfix'
  - lib/auth/authelia/authelia.config.yml
  - lib/media/gitea/gitea.libsonnet
  - lib/monitoring/grafana/grafana.libsonnet
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Contexto

Actualmente 3 servicios configuran SMTP directamente contra Mailgun (`smtp.eu.mailgun.org:587`), cada uno con sus propias credenciales:
- **Authelia** (`lib/auth/authelia/authelia.config.yml`)
- **Gitea** (`lib/media/gitea/gitea.libsonnet`)
- **Grafana** (`lib/monitoring/grafana/grafana.libsonnet`)

Esto implica credenciales duplicadas y ninguna garantía de entrega (si Mailgun está caído, el correo se pierde).

## Objetivo

Desplegar un relay SMTP interno con **boky/postfix** que centralice el envío de correos:

```
Authelia  ──┐
Gitea     ──┼──► smtp-relay.system (boky/postfix) ──► smtp.eu.mailgun.org
Grafana   ──┘
```

### Beneficios
- **Una sola fuente** de credenciales Mailgun (SealedSecret cluster-wide)
- **Cola con reintentos** — Postfix reintenta durante 5 días con backoff exponencial si Mailgun falla
- **Observabilidad** vía logs estructurados (JSON) en Loki + dashboard Grafana
- Los servicios internos envían sin auth a `smtp-relay.system.svc.cluster.local:587`

## Componentes

### boky/postfix (relay SMTP)

**Imagen**: `boky/postfix`

**Env vars clave**:
| Variable | Valor |
|----------|-------|
| `RELAYHOST` | `smtp.eu.mailgun.org:587` |
| `RELAYHOST_USERNAME` | `nas@mail.danielramos.me` |
| `RELAYHOST_PASSWORD` | (SealedSecret) |
| `ALLOWED_SENDER_DOMAINS` | `danielramos.me mail.danielramos.me` |
| `POSTFIX_myhostname` | `smtp-relay` |
| `POSTFIX_smtp_tls_security_level` | `encrypt` |
| `POSTFIX_message_size_limit` | `26214400` (25MB) |
| `LOG_FORMAT` | `json` |

**Health check**: `/scripts/healthcheck.sh` (interval 30s, timeout 5s, retries 3)

**Almacenamiento**: hostPath directo a `/data/smtp-relay` montado en `/var/spool/postfix` para que la cola sobreviva reinicios del pod. Sin PV/PVC — mismo patrón que el resto de servicios en `/data/*`.

**Docs**: https://github.com/bokysan/docker-postfix

### Observabilidad (Loki + Grafana)

En lugar de un exporter Prometheus (kumina/postfix_exporter), aprovechamos que Loki ya recoge los logs del cluster. Con `LOG_FORMAT=json` los logs son estructurados y fáciles de parsear.

**Queries LogQL para dashboard**:
```logql
# Correos enviados
{app="smtp-relay"} | json | status="sent"

# Correos diferidos
{app="smtp-relay"} | json | status="deferred"

# Bounces
{app="smtp-relay"} | json | status="bounced"

# Ratio de entregas por hora
sum(count_over_time({app="smtp-relay"} | json | status="sent" [1h]))

# Errores de conexión
{app="smtp-relay"} | json |= "connection timed out"
```

## Implementación

### Paso 1: Crear módulo `lib/system/smtp-relay/smtp-relay.libsonnet`
- Deployment con 1 container (solo postfix, sin sidecar)
- hostPath directo a `/data/smtp-relay` montado en `/var/spool/postfix` (sin PV/PVC)
- Service ClusterIP en puerto 587 (SMTP)
- SealedSecret cluster-wide para `RELAYHOST_PASSWORD` (reutilizar la contraseña SMTP de Mailgun existente)

### Paso 2: Añadir al environment `environments/system/`
- Importar el módulo y añadirlo al `main.jsonnet`
- Añadir versión de la imagen a `environments/versions.json`

### Paso 3: Reconfigurar servicios consumidores
- **Authelia**: cambiar `notifier.smtp.address` a `smtp://smtp-relay.system.svc.cluster.local:587`, quitar username/password
- **Gitea**: cambiar `GITEA__mailer__SMTP_ADDR` a `smtp-relay.system.svc.cluster.local`, quitar USER y contraseña
- **Grafana**: cambiar `GF_SMTP_HOST` a `smtp-relay.system.svc.cluster.local:587`, quitar USER y contraseña

### Paso 4: Limpiar secrets SMTP duplicados
- Eliminar las credenciales SMTP de los secrets de Authelia, Gitea y Grafana

### Paso 5: Dashboard Grafana
- Crear dashboard con paneles LogQL: correos enviados, diferidos, bounces, errores de conexión
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 smtp-relay desplegado en namespace system con boky/postfix (container único, sin sidecar)
- [ ] #2 Cola persistente via hostPath en /data/smtp-relay (sin PV/PVC)
- [ ] #3 Credenciales Mailgun en un único SealedSecret cluster-wide
- [ ] #4 Authelia, Gitea y Grafana reconfigurados para usar smtp-relay.system.svc.cluster.local:587 sin auth
- [ ] #5 Credenciales SMTP eliminadas de los secrets individuales de cada servicio
- [ ] #6 Health check configurado en el container de postfix
- [ ] #7 Logs en formato JSON (LOG_FORMAT=json) recogidos por Loki
- [ ] #8 Dashboard en Grafana con paneles LogQL (sent, deferred, bounced)
- [ ] #9 Correos se envían correctamente a través del relay (test manual)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Puerto interno y TLS

`boky/postfix` escucha en el puerto 587 y acepta conexiones **sin TLS y sin auth** desde redes internas. Por defecto `POSTFIX_mynetworks` incluye `127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16`, que cubre los pods de K8s. No hace falta usar el puerto 25.

### Cambios específicos por servicio

| Servicio | Config actual | Config nueva |
|----------|--------------|-------------|
| **Authelia** | `address: smtp://smtp.eu.mailgun.org:587`, `username`, `password` | `address: smtp://smtp-relay.system.svc.cluster.local:587`, quitar `username` y `password` |
| **Gitea** | `PROTOCOL=smtps`, `SMTP_ADDR=smtp.eu.mailgun.org`, `SMTP_PORT=587`, `USER` | `PROTOCOL=smtp`, `SMTP_ADDR=smtp-relay.system.svc.cluster.local`, `SMTP_PORT=587`, quitar `USER` |
| **Grafana** | `GF_SMTP_HOST=smtp.eu.mailgun.org:587`, `GF_SMTP_USER` | `GF_SMTP_HOST=smtp-relay.system.svc.cluster.local:587`, quitar `GF_SMTP_USER` |

**Importante**: En Gitea cambiar `PROTOCOL` de `smtps` a `smtp` porque la conexión interna no necesita TLS.

## Versión de imagen

`boky/postfix:v5.1.0` — pinear en `environments/versions.json`.

## Ejecución como root (obligatorio)

Postfix requiere que el master process corra como **root** — es así by design. Los subprocesos corren como `postfix:postfix` (UID 100:101 en Alpine). No se puede usar `runAsUser: 1000` como otros servicios del repo.

El hostPath `/data/smtp-relay` será gestionado internamente por Postfix con sus propios UIDs (100/101). No requiere preparación previa de permisos.

## Migración

Todo de golpe en un solo PR: desplegar relay + reconfigurar los 3 servicios + limpiar secrets. Es un homelab, no necesita rollout incremental.

## Testing

Tras desplegar, enviar correo de test manual a `danielramosacosta1@gmail.com` para verificar entrega end-to-end.
<!-- SECTION:NOTES:END -->
