---
id: NASKS-76
title: Hardening del plugin OIDC de FacturaScripts
status: To Do
assignee: []
created_date: '2026-06-27 08:18'
labels:
  - business
  - facturascripts
  - oidc
  - tech-debt
dependencies:
  - NASKS-60
references:
  - 'https://github.com/jumbojett/OpenID-Connect-PHP'
  - 'https://www.authelia.com/integration/openid-connect/introduction/'
priority: medium
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 📌 TLDR

Reducir la deuda técnica del plugin propio OIDC (login con Authelia) de FacturaScripts: dejar de duplicar la lógica de sesión/cookies del core, delegar la verificación de JWT en la librería ya vendorizada y dejar de acceder a superglobales. Detectado al auditar el plugin para el upgrade a 2026.3 (NASKS-60).

## 🎯 Contexto funcional

OIDC es un plugin custom (no del marketplace) que aporta el SSO de acceso a FacturaScripts vía Authelia. Funciona y es compatible con 2026.3, pero su implementación tiene varios puntos frágiles, especialmente la **duplicación de la lógica de sesión/cookies del core**: como 2026 endurece sesiones/2FA, esa copia puede divergir del core y romper el login en futuros upgrades. Es el flanco más sensible. Además reinventa criptografía (verificación de JWT a mano) teniendo la librería que lo hace, lo cual es un riesgo de seguridad. El objetivo es alinear el plugin con la API del core para que sea robusto ante futuras versiones y más seguro.

## ⚙️ Contexto técnico

Plugin en hostPath `/data/facturascripts/plugins/OIDC`. Hallazgos del code-review (contra core `v2025.81`/`v2026.3`):

- **Sesión/cookies duplicadas**: `OidcCallback::loginUser()` y `saveCookies()` reimplementan a mano `Session::set('user')`, `User::newLogkey()` y las cookies `fsNick`/`fsLogkey`/`fsLang`. Ocurre porque `OidcCallback implements ControllerInterface` (no extiende `Core\Controller\Login`), por lo que no puede reusar el método `protected` del core. Hay que delegar en el core o, si no es viable, centralizar/justificar para no divergir.
- **Verificación de JWT manual**: `OidcCallback::decodeAndVerifyJwt()` parsea base64url, valida `alg=RS256`, descarga el JWKS y hace `openssl_verify`, **teniendo ya `jumbojett/openid-connect-php` (`^1.0`) vendorizado**. Debe delegarse en la librería. Detalle laxo: si el JWT no trae `kid`, coge la primera clave del JWKS.
- **Superglobales**: accesos directos a `$_SERVER['HTTP_USER_AGENT']`, `HTTP_X_FORWARDED_PROTO`, `HTTPS` en vez de `Core\Request`/`Core\Http` (que el plugin ya usa en otros sitios) → frágil detrás de proxy/Traefik.
- **Logging mixto**: algunos catch usan `error_log()` directo en vez de `Tools::log()` → esos errores no llegan a los canales de FS/Loki.
- **Override de ruta `/login`** vía `Kernel::addRoute` apuntando a su subclase `Login extends CoreLogin`: funciona (el controlador Login es estable en 2026.3) pero acopla al sistema de rutas del core; revisar al tocar lo anterior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 OidcCallback deja de reimplementar a mano el establecimiento de sesión/login (Session::set('user'), newLogkey, cookies fsNick/fsLogkey/fsLang) y delega en el mecanismo del core; si por implementar ControllerInterface no es posible reusarlo, se centraliza/justifica para no divergir del core en sesiones/2FA
- [ ] #2 La verificación del JWT de userinfo se hace con la librería vendorizada jumbojett/openid-connect-php, eliminando la implementación manual (openssl_verify + parseo de JWKS)
- [ ] #3 Se sustituyen los accesos directos a $_SERVER[...] por la abstracción Request/Http del core
- [ ] #4 Logging unificado en Tools::log() (sin error_log() directos)
- [ ] #5 El login OIDC con Authelia sigue funcionando tras los cambios (verificado en runtime)
<!-- AC:END -->
