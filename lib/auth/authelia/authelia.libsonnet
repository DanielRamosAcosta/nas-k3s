local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'auth/authelia/authelia.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local autheliaConfig = importstr './authelia.config.yml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('authelia', replicas=1, containers=[
                  container.new('authelia', u.image(versions.authelia.image, versions.authelia.version)) +
                  container.withPorts([containerPort.new('http', 9091)]) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealed_secret) +
                    u.envVars.fromSealedSecret(self.sealed_secret_shared) +
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.configuration, '/config'),
                    u.volumeMount.fromSealedSecretFile(self.sealedUsersDatabase, '/config'),
                    u.volumeMount.fromSealedSecretFile(self.sealedJwksKey, '/config/secrets/oidc/jwks'),
                  ]) +
                  u.probes.http('/api/health', 9091),
                ]) +
                u.injectFiles([self.configuration, self.sealedUsersDatabase, self.sealedJwksKey]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment) + u.prometheus(port='9959'),

    configuration: u.configMap.forFile('configuration.yml', autheliaConfig),

    sealedUsersDatabase: u.sealedSecret.forFile('users_database.yml', secrets.usersDatabase),

    configEnv: u.configMap.forEnv(self.deployment, {
      X_AUTHELIA_CONFIG_FILTERS: 'template',
    }),

    sealedJwksKey: u.sealedSecret.forFile('rsa.2048.key', secrets.jwksKey),

    sealed_secret: u.sealedSecret.forEnv(self.deployment, secrets.authelia),

    sealed_secret_shared: u.sealedSecret.wide.forEnvNamed('authelia-shared-sealed-secret', { AUTHELIA_STORAGE_POSTGRES_PASSWORD: postgresSecrets.userAuthelia }),

    ingressRoute: u.ingressRoute.from(self.service, 'auth.danielramos.me'),
  },
}
