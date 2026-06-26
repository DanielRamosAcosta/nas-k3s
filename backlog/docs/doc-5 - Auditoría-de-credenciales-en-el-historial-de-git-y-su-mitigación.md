---
id: doc-5
title: Auditoría de credenciales en el historial de git y su mitigación
type: guide
created_date: '2026-06-26 21:42'
tags:
  - security
  - secrets
  - audit
---
## Contexto

Este repositorio es público. Antes de la arquitectura actual (Jsonnet + Tanka + Sealed Secrets) existió una arquitectura previa cuyos commits permanecen en el historial de git. Se realizó una auditoría para localizar secretos que pudieran haber quedado expuestos en claro o en base64 en commits antiguos, y verificar que ninguno siga siendo válido hoy.

**Metodología:** toda verificación de "¿sigue activa?" se hizo comparando *fingerprints/hashes* derivados (nunca valores en claro) contra el estado real en producción — vía el endpoint público correspondiente o el clúster — sin imprimir jamás un secreto. Los detalles concretos (commits, rutas, hashes) se mantienen **fuera de este documento público** a propósito, para no facilitar la localización de los valores en el historial.

## Resultado general

✅ **Ninguna credencial activa está comprometida.** Toda credencial que estuvo presente en commits antiguos está rotada, retirada por cambio de arquitectura, o pertenecía a un componente que ya no se despliega.

## Estado por credencial

| Credencial (histórica) | Estado | Notas |
|---|---|---|
| Clave privada de firma OIDC del IdP | ✅ Rotada | La clave en uso hoy es distinta; verificada contra el JWKS público en vivo. Gestionada hoy como SealedSecret. |
| Credencial SMTP del proveedor de correo | ✅ Rotada y verificada | Verificado en el panel del proveedor: existe un único usuario SMTP y solo conserva la contraseña actual, que difiere de la histórica → la antigua ya está invalidada. Además la arquitectura migró a un relay interno. **No hay nada que revocar.** |
| Contraseña de base de datos | ✅ Rotada | No coincide con ninguna credencial viva (superusuario, backup ni usuarios lógicos). Al ser interna, rotada = inservible. |
| Secreto de cliente OIDC | ✅ Rotado | El secreto en uso hoy no valida contra el hash histórico. Además el valor histórico era un *placeholder* de ejemplo de la documentación del IdP, no un secreto productivo. |
| Hashes de contraseñas de usuarios | ✅ No expuestos hoy | Hoy el fichero de usuarios versionado lleva *placeholders*; los hashes reales viven cifrados (SealedSecret) e se inyectan en runtime. En el historial solo quedaron los hashes de un par de cuentas antiguas. |
| Clave CSRF del dashboard de K8s | ⚪ No aplica | El componente fue retirado: no se despliega ni existe en el clúster. Sin clave activa que pueda coincidir. |

## Gestión de secretos actual (correcta)

- Todos los secretos productivos se gestionan con **Bitnami Sealed Secrets**: el valor cifrado se commitea, solo el controlador del clúster lo descifra. Es seguro tenerlo en un repo público.
- El fichero de usuarios del IdP usa placeholders de variables de entorno en git; los hashes reales se inyectan vía init container (`envsubst`) desde un SealedSecret.

## Acciones pendientes (higiene, no urgentes)

1. **Cambio de contraseña** para las cuentas de usuario cuyos hashes estuvieron en commits antiguos. Un re-hash con nuevo salt no protege si la contraseña en claro se reutilizó, porque el hash antiguo sigue siendo crackeable offline desde el historial. (Revisar también cuentas que comparten la misma contraseña.)
2. **Decisión sobre el historial:** purgar los secretos antiguos del historial (reescritura con filter-repo/BFG + force-push) es **defensa en profundidad / cosmético** dado que todo está rotado. Solo merece la pena si se quiere eliminar el rastro residual; rompe forks/clones existentes.
3. **Completitud (opcional):** barrer el historial completo del fichero de usuarios por si más cuentas tuvieron su hash en claro en commits posteriores antes de migrar al SealedSecret.

## Conclusión

Desde el punto de vista de **credenciales activas**, el repositorio es seguro de mantener público. Lo que resta son decisiones de higiene y privacidad, ninguna con impacto de seguridad activo.
