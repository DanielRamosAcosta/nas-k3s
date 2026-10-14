from settings.main import *  # noqa: F401,F403

# Override SSO-only sobre settings.main (via DJANGO_SETTINGS_MODULE=settings.custom).
#
# Abre SOLO el alta por login social (OIDC) para auto-aprovisionar usuarios en su
# primer login contra Authelia. El alta LOCAL sigue cerrada: wger ata
# is_open_for_signup a ALLOW_REGISTRATION (=False) via su ACCOUNT_ADAPTER, que no
# tocamos. El adapter vive en un modulo aparte (no se puede importar en tiempo de
# carga de settings) y se referencia por ruta; allauth lo importa de forma diferida.
SOCIALACCOUNT_ADAPTER = 'wger_sso_adapter.OpenSocialSignupAdapter'

# Si ya existe una cuenta local con el mismo email verificado, enlaza en vez de
# crear una duplicada (Authelia envia email_verified). Evita duplicar historial.
SOCIALACCOUNT_EMAIL_AUTHENTICATION = True
SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT = True
