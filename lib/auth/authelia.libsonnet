local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

local autheliaConfig = importstr './authelia.config.yml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='ghcr.io/authelia/authelia', version):: {
    deployment: deployment.new('authelia', replicas=1, containers=[
                  container.new('authelia', u.image(image, version)) +
                  container.withPorts([containerPort.new('http', 9091)]) +
                  container.withEnv(
                    u.envVars.fromSecret(self.secrets) +
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.configuration, '/config'),
                    u.volumeMount.fromFile(self.usersDatabase, '/config'),
                    u.volumeMount.fromFile(self.secretJwksKey, '/config/secrets/oidc/jwks'),
                  ]),
                ]) +
                u.injectFiles([self.configuration, self.usersDatabase, self.secretJwksKey]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment) + u.prometheus(port='9959'),

    configuration: u.configMap.forFile('configuration.yml', autheliaConfig),

    usersDatabase: u.secret.forFile('users_database.yml', std.manifestYamlDoc({
      users: {
        dani: {
          disabled: false,
          displayname: 'Dani',
          given_name: 'Daniel',
          family_name: 'Ramos Acosta',
          picture: 'https://2.gravatar.com/avatar/bd9cf3cfa5c4875128bdd435d7f304403c6c883442670a1cd201abf85d3858d1?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Europe/Madrid',
          password: s.AUTHELIA_PASSWORD_DANI,
          email: 'danielramosacosta1@gmail.com',
          groups: [
            'admins',
          ],
        },
        admin: {
          disabled: false,
          displayname: 'Dani',
          given_name: 'Daniel',
          family_name: 'Ramos Acosta',
          picture: 'https://2.gravatar.com/avatar/bd9cf3cfa5c4875128bdd435d7f304403c6c883442670a1cd201abf85d3858d1?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Europe/Madrid',
          password: s.AUTHELIA_PASSWORD_DANI,
          email: 'danielramosacosta1+admin@gmail.com',
          groups: [
            'admins',
          ],
        },
        cris: {
          disabled: false,
          displayname: 'Cris',
          given_name: 'Cristina',
          family_name: 'Guardia Trujillo',
          picture: 'https://2.gravatar.com/avatar/3780877d4745ddac6f733933240f62fddc3c4ded1a78571ac710b36d6dd96673?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Europe/Madrid',
          password: s.AUTHELIA_PASSWORD_CRIS,
          email: 'ivhcristinaguardia@gmail.com',
          groups: [],
        },
        alex: {
          disabled: false,
          displayname: 'Alex',
          given_name: 'Alexander',
          family_name: 'Ramos García',
          picture: 'https://2.gravatar.com/avatar/6bc544db0e0d3242bb0f72894672cfb24635d29f02a2c9164368a9612b923374?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Atlantic/Canary',
          password: s.AUTHELIA_PASSWORD_ALEX,
          email: 'alexsaxramos@gmail.com',
          groups: [],
        },
        ana: {
          disabled: false,
          displayname: 'Ana',
          given_name: 'Ana',
          family_name: 'Acosta García',
          picture: 'https://1.gravatar.com/avatar/c1bb07abcadf81a38641e42d64a3181ca22c3807b49abc49798ce72e9cf45007?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Atlantic/Canary',
          password: s.AUTHELIA_PASSWORD_ANA,
          email: 'ana_acosta@live.com',
          groups: [],
        },
        gabriel: {
          disabled: false,
          displayname: 'Gabriel',
          given_name: 'Gabriel',
          family_name: 'Ramos Acosta',
          picture: 'https://2.gravatar.com/avatar/f7454bbabbe58703669567dfe8bdeb80cfc79ffef303ca8f8ba12fc6238521c7?size=512&d=initials',
          locale: 'es-ES',
          zoneinfo: 'Atlantic/Canary',
          password: s.AUTHELIA_PASSWORD_GABRIEL,
          email: 'gabrielramosacosta1@gmail.com',
          groups: [],
        },
      },
    })),

    configEnv: u.configMap.forEnv(self.deployment, {
      X_AUTHELIA_CONFIG_FILTERS: 'template',
    }),

    secretJwksKey: u.secret.forFile('rsa.2048.key', s.AUTHELIA_IDENTITY_PROVIDERS_OIDC_JWKS_0_KEY),

    secrets: u.secret.forEnv(self.deployment, {
      AUTHELIA_STORAGE_ENCRYPTION_KEY: s.AUTHELIA_STORAGE_ENCRYPTION_KEY,
      AUTHELIA_STORAGE_POSTGRES_PASSWORD: s.POSTGRES_PASSWORD_AUTHELIA,
      AUTHELIA_SESSION_SECRET: s.AUTHELIA_SESSION_SECRET,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_IMMICH_CLIENT_ID: s.AUTHELIA_OIDC_IMMICH_CLIENT_ID,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_IMMICH_CLIENT_SECRET_DIGEST: s.AUTHELIA_OIDC_IMMICH_CLIENT_SECRET_DIGEST,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_SFTPGO_CLIENT_ID: s.AUTHELIA_OIDC_SFTPGO_CLIENT_ID,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_SFTPGO_CLIENT_SECRET_DIGEST: s.AUTHELIA_OIDC_SFTPGO_CLIENT_SECRET_DIGEST,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_GRAFANA_CLIENT_ID: s.AUTHELIA_OIDC_GRAFANA_CLIENT_ID,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_GRAFANA_CLIENT_SECRET_DIGEST: s.AUTHELIA_OIDC_GRAFANA_CLIENT_SECRET_DIGEST,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_GITEA_CLIENT_ID: s.AUTHELIA_OIDC_GITEA_CLIENT_ID,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_GITEA_CLIENT_SECRET_DIGEST: s.AUTHELIA_OIDC_GITEA_CLIENT_SECRET_DIGEST,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_JELLYFIN_CLIENT_ID: s.AUTHELIA_OIDC_JELLYFIN_CLIENT_ID,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_JELLYFIN_CLIENT_SECRET_DIGEST: s.AUTHELIA_OIDC_JELLYFIN_CLIENT_SECRET_DIGEST,
      IDENTITY_PROVIDERS_OIDC_CLIENTS_BOOKLORE_CLIENT_ID: s.AUTHELIA_OIDC_BOOKLORE_CLIENT_ID,
      AUTHELIA_NOTIFIER_SMTP_PASSWORD: s.SMTP_PASSWORD,
    }),

    ingressRoute: u.ingressRoute.from(self.service, 'auth.danielramos.me'),
  },
}
