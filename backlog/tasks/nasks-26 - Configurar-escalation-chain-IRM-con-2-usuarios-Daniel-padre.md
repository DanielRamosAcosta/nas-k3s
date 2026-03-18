---
id: NASKS-26
title: Configurar escalation chain IRM con 2 usuarios (Daniel + padre)
status: Done
assignee: []
created_date: '2026-03-18 08:20'
updated_date: '2026-03-18 20:49'
labels:
  - infrastructure
  - monitoring
  - refined
dependencies: []
priority: medium
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Configurar IRM en Grafana Cloud con escalation chains para 2 usuarios (Daniel + Alexander).

## Usuarios
- **Daniel** (danielramosacosta) — ya configurado, notificaciones siempre en modo Important (push agresivo + email)
- **Alexander** (alexsaxramos@gmail.com) — ya invitado y registrado, solo email

## Escalation Chains

### 1. Default (alertas generales del webhook)
1. Notify Daniel (Important)
2. Wait 10 minutos
3. Si no hay ACK → Notify Alexander (email)

### 2. Critical (Probe / Synthetic Monitoring)
1. Notify Daniel (Important) + Alexander (email) — ambos a la vez

## Routing en OnCall
- Alerts con label `namespace=synthetic_monitoring` → chain **Critical**
- Todo lo demás → chain **Default**

## Contexto
- Integración "NAS K3s Alerting" ya existe y funciona
- Contact point en Grafana apunta al webhook de IRM
- Alexander ya invitado a Grafana Cloud
- Notification policy de Grafana Alerting: todo va a OnCall, routing granular se hace dentro de OnCall
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Alexander tiene notification rules configuradas (Default: email, Important: email)
- [x] #2 Escalation chain 'Default': Daniel (Important) → 10 min wait → Alexander (email)
- [x] #3 Escalation chain 'Critical': Daniel (Important) + Alexander (email) simultáneo
- [x] #4 Route en OnCall: namespace=synthetic_monitoring → Critical chain
- [x] #5 Route default en OnCall → Default chain
- [ ] #6 Test: alerta de prueba llega a Daniel correctamente
- [ ] #7 Test: probe failure notifica a ambos simultáneamente
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Configuración realizada\n\n### Labels Schema (integración NAS K3s Alerting)\n- `service_name` → `{{ payload.commonLabels.service_name }}`\n- `namespace` → `{{ payload.commonLabels.namespace }}` (nuevo)\n\n### Escalation Chains\n- **NAS Critical Alerts** (ID: FUBPUJPQ3T5IQ): Daniel Important → Wait 10 min → Alexander Default\n- **NAS Critical Probe** (ID: FY4C1JG5KFCXJ): Daniel Important + Alexander simultáneo\n\n### Routes (integración CYKRDJJHTZ9RJ)\n- Route custom: namespace=synthetic_monitoring → NAS Critical Probe\n- Route default: todo lo demás → NAS Critical Alerts\n\n### Notification rules de Alexander (UV4A3XZ8PD88V)\n- Default: Email\n- Important: Email\n\n### Pendiente de verificar\n- Test real con probe failure para confirmar routing\n- Test real con alerta genérica para confirmar escalado gradual
<!-- SECTION:NOTES:END -->
