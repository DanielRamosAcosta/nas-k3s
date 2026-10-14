import os
from allauth.socialaccount.models import SocialApp
from django.contrib.sites.models import Site
from django.contrib.auth import get_user_model
U = get_user_model()
# Registro del proveedor OIDC (fila en Postgres, fuera de git). Idempotente y
# reproducible desde cero: lee client_id/secret de env (SealedSecret).
app, _ = SocialApp.objects.update_or_create(
    provider='openid_connect', provider_id='authelia',
    defaults=dict(name='Authelia',
                  client_id=os.environ['OIDC_CLIENT_ID'],
                  secret=os.environ['OIDC_CLIENT_SECRET'],
                  settings={'server_url': 'https://auth.danielramos.me'}))
app.sites.add(Site.objects.get(id=1))
# SSO-only: anula cualquier contrasena local usable. Mata el login local y,
# de paso, el password reset de Django (PasswordResetForm.get_users omite las
# cuentas sin contrasena usable, asi que no envia email de reset a nadie).
for u in U.objects.all():
    if u.has_usable_password():
        u.set_unusable_password()
        u.save(update_fields=['password'])
# Designa al admin del gym. En un rebuild desde cero la cuenta no existe hasta
# su primer login OIDC (se auto-aprovisiona); el siguiente sync la promociona.
admin_username = os.environ.get('OIDC_ADMIN_USERNAME')
if admin_username:
    admin = U.objects.filter(username=admin_username).first()
    if admin and not (admin.is_superuser and admin.is_staff):
        admin.is_superuser = True
        admin.is_staff = True
        admin.save(update_fields=['is_superuser', 'is_staff'])
