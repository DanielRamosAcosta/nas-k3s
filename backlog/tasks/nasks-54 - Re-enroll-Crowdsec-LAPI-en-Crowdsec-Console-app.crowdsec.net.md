---
id: NASKS-54
title: Re-enroll Crowdsec LAPI en Crowdsec Console (app.crowdsec.net)
status: To Do
assignee: []
created_date: '2026-04-22 20:34'
labels:
  - infra
  - crowdsec
  - observability
  - followup-nasks-53
dependencies: []
priority: low
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Context

En NASKS-53 desplegamos Crowdsec full stack (agent + LAPI) y pasamos un `ENROLL_KEY` al entrypoint para registrar la instancia contra [app.crowdsec.net](https://app.crowdsec.net) automáticamente. El primer intento manual de `cscli console enroll` que lancé al debugear falló al escribir `console.yaml` (estaba mounteado read-only desde un ConfigMap), pero el key **sí se consumió server-side** antes del fallo local. Resultado:

- El LAPI local cree que está enrolado: `Instance already enrolled. You can use '--overwrite' to force enroll`.
- La Console UI en cambio reporta: `Machine is not enrolled in the console, can't synchronize with the console`.

Nadie se ve a nadie. Hay que generar un key nuevo y hacer `cscli console enroll --overwrite` para reparar el vínculo. Con el fix de `config.console.yaml` (ya no lo montamos desde ConfigMap), la escritura ahora funciona.

## Outcome esperado

- La máquina `nas-k3s` aparece "enrolada + aprobada" en Security Engines en la Console.
- Se ven decisions, alerts, hub status, scenarios disparados desde la UI.
- Las decisions de Crowdsec comunidad se sincronizan (bloquear IPs que otros usuarios del Hub han reportado).

## Pasos

1. [Console UI](https://app.crowdsec.net) → Security Engines → **Add Engine** → copia el nuevo `<ENROLL_KEY>`.
2. Sella el key nuevo:
   ```bash
   echo -n '<ENROLL_KEY>' | ./scripts/encrypt-secret.sh system crowdsec-console
   ```
3. Reemplaza el valor de `crowdsecConsoleEnrollmentKey` en `lib/system/crowdsec/crowdsec.secrets.json` con el nuevo sealed string.
4. Commit + push. ArgoCD sincroniza y el LAPI pod se reinicia con el `ENROLL_KEY` nuevo en env.
5. El entrypoint NO usa `--overwrite`, así que tras el reinicio seguirá diciendo "already enrolled". Forzar a mano **una sola vez**:
   ```bash
   kubectl -n system exec deploy/crowdsec-lapi -- \
     cscli console enroll --overwrite --name nas-k3s '<ENROLL_KEY_PLAINTEXT>'
   ```
6. Console UI → Security Engines → la máquina `nas-k3s` aparece pending → **Accept**.
7. Verifica dashboard: Decisions / Alerts / Hub status rellenos.

## Fix adicional recomendado (opcional)

En `lib/system/crowdsec/crowdsec.libsonnet`, actualmente dependemos de que el entrypoint vea `ENROLL_KEY` y el vínculo no esté previamente rotado. Para hacer idempotente el enroll en futuros rollouts (ej. si el key cambia), se podría:

- Patchear el entrypoint script (via extra init container) para añadir `--overwrite` cuando `ENROLL_FORCE_OVERWRITE=true`.
- O más simple: aceptar que cambiar de key requiere un `cscli enroll --overwrite` manual (es raro).

Documentar este caveat en el README del módulo.

## Acceptance criteria

- [ ] Nuevo enrollment key generado en Console y sellado en `crowdsec.secrets.json`.
- [ ] LAPI pod reiniciado con ENROLL_KEY nuevo tras ArgoCD sync.
- [ ] `cscli console enroll --overwrite` ejecutado con éxito dentro del pod.
- [ ] Engine `nas-k3s` aprobado en Console UI.
- [ ] Console dashboard muestra `Decisions: N` (aunque sea 0 inicialmente), `Alerts: N`, `Hub: ok`.
- [ ] Logs del LAPI ya no muestran `Machine is not enrolled in the console`.

## No scope

- Dashboard Grafana para métricas de Crowdsec (tarea aparte).
- AppSec / WAF engine de Crowdsec.
- Bouncers adicionales más allá del ya wireado en Traefik.
<!-- SECTION:DESCRIPTION:END -->
