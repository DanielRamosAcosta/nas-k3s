---
title: 'Alertas Grafana para SMTP relay (bounces, deferred, relay caído)'
status: Done
created_date: '2026-03-20 19:41'
labels:
  - monitoring
  - smtp
  - alerting
dependencies:
  - "[[Centralizar SMTP con relay Postfix (boky postfix)]]"
priority: 2
ordinal: 0.48828125
---

## Description

## Contexto

Tras desplegar el relay SMTP centralizado ([[Centralizar SMTP con relay Postfix (boky postfix)]]), necesitamos alertas para detectar problemas de entrega de correo. Sin alertas, fallos como credenciales Mailgun expiradas, cola bloqueada o DNS roto pasarían desapercibidos.

## Alertas propuestas

Basadas en los logs JSON del relay (`{app="smtp-relay"} | json`):

### 1. Bounces excesivos
- **Condición**: más de 5 correos con `status="bounced"` en la última hora
- **Severidad**: warning
- **Indica**: direcciones inválidas, problema con Mailgun, o relay mal configurado

### 2. Cola de deferred creciendo
- **Condición**: más de 20 correos con `status="deferred"` en la última hora
- **Severidad**: critical
- **Indica**: Mailgun caído, credenciales expiradas, o problema de red/DNS

### 3. Relay sin actividad (posible caída)
- **Condición**: 0 correos con `status="sent"` en las últimas 24h
- **Severidad**: warning
- **Indica**: relay caído o ningún servicio está enviando correos (puede ser normal en periodos de baja actividad)

### 4. Errores de conexión a Mailgun
- **Condición**: logs con `connection timed out` o `connection refused` en la última hora
- **Severidad**: critical
- **Indica**: problema de red, DNS, o Mailgun caído

## Decisiones pendientes
- ¿A dónde se notifica? (Slack, Discord, email — pero si el relay está roto, email no sirve)
- Umbrales exactos a ajustar tras observar tráfico real
- ¿Crear dashboard dedicado o añadir panel de alertas al dashboard general SMTP?

## Acceptance Criteria
- [ ] #1 Alertas configuradas en Grafana con queries LogQL sobre los logs del smtp-relay
- [ ] #2 Al menos alertas para: bounces excesivos, deferred creciendo, errores de conexión
- [ ] #3 Canal de notificación configurado (no email, ya que depende del propio relay)
- [ ] #4 Umbrales ajustados tras observar tráfico real

## Implementation Notes

## Incertidumbre: LOG_FORMAT=json

La documentación de `boky/postfix` **no especifica qué campos JSON genera**. Las queries LogQL propuestas en esta tarea son una suposición basada en el formato estándar de logs de Postfix.

**Plan**: tras desplegar el relay ([[Centralizar SMTP con relay Postfix (boky postfix)]]), inspeccionar los logs reales en Loki → ajustar queries del dashboard y alertas según los campos disponibles.
