---
id: NASKS-54
title: Re-enroll Crowdsec LAPI en Crowdsec Console (app.crowdsec.net)
status: Done
assignee: []
created_date: '2026-04-22 20:34'
updated_date: '2026-08-09 19:04'
labels:
  - infra
  - crowdsec
  - observability
  - followup-nasks-53
dependencies: []
priority: low
ordinal: 1000
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

- [x] Nuevo enrollment key generado en Console y sellado en `crowdsec.secrets.json`.
- [x] LAPI pod reiniciado con ENROLL_KEY nuevo tras ArgoCD sync.
- [x] `cscli console enroll --overwrite` ejecutado con éxito dentro del pod.
- [x] Engine `nas-k3s` aprobado en Console UI.
- [x] Console dashboard muestra `Decisions: N` (aunque sea 0 inicialmente), `Alerts: N`, `Hub: ok`.
- [x] Logs del LAPI ya no muestran `Machine is not enrolled in the console`.

## No scope

- Dashboard Grafana para métricas de Crowdsec (tarea aparte).
- AppSec / WAF engine de Crowdsec.
- Bouncers adicionales más allá del ya wireado en Traefik.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Vínculo LAPI↔Console reparado. Nuevo enrollment key generado y sellado en crowdsec.secrets.json; LAPI reiniciado vía ArgoCD y `cscli console enroll --overwrite` forzado una vez. Verificado en logs (Loki): el LAPI reciente muestra `Machine is enrolled in the console, Loading PAPI Client` y ya NO aparece `Machine is not enrolled in the console`. Console UI confirmada por el usuario: engine nas-k3s aprobado y dashboard (Decisions/Alerts/Hub) con datos.
<!-- SECTION:FINAL_SUMMARY:END -->
