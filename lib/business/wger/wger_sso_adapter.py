from allauth.socialaccount.adapter import DefaultSocialAccountAdapter


class OpenSocialSignupAdapter(DefaultSocialAccountAdapter):
    """Permite el alta por login social (OIDC) aunque el registro local este
    cerrado.

    wger ata ``is_open_for_signup`` a ``ALLOW_REGISTRATION`` (=False) a traves de
    su ``ACCOUNT_ADAPTER``, y el adapter social por defecto delega en el. Aqui
    abrimos solo la via social para que cualquier usuario de Authelia se
    auto-aprovisione una cuenta en su primer login, sin reabrir el registro local.
    """

    def is_open_for_signup(self, request, sociallogin):
        return True
