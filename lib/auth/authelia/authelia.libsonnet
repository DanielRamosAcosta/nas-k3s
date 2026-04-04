local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'auth/authelia/authelia.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local autheliaConfig = importstr './authelia.config.yml';
local usersDatabase = importstr './users_database.yml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('authelia', replicas=1, containers=[
                  container.new('authelia', u.image(versions.authelia.image, versions.authelia.version)) +
                  container.withPorts([containerPort.new('http', 9091)]) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealedSecret) +
                    u.envVars.fromSealedSecret(self.sealedSecretShared) +
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.configuration, '/config'),
                    volumeMount.new('merged-users', '/config/users_database.yml') + volumeMount.withSubPath('users_database.yml') + volumeMount.withReadOnly(true),
                    u.volumeMount.fromSealedSecretFile(self.sealedJwksKey, '/config/secrets/oidc/jwks'),
                  ]) +
                  u.probes.http('/api/health', 9091),
                ]) +
                deployment.spec.template.spec.withInitContainers(
                  container.new('render-users', u.image(versions.envsubst.image, versions.envsubst.version)) +
                  container.withCommand(['sh', '-c', 'envsubst < /data/users_database.yml > /output/users_database.yml']) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealedUserPasswords),
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.usersDatabasePublic, '/data'),
                    volumeMount.new('merged-users', '/output'),
                  ])
                ) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromConfigMap(self.configuration),
                  u.volume.fromSealedSecret(self.sealedJwksKey),
                  u.volume.fromConfigMap(self.usersDatabasePublic),
                  volume.fromEmptyDir('merged-users'),
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment) + u.metrics(port='9959'),

    configuration: u.configMap.forFile('configuration.yml', autheliaConfig),

    usersDatabasePublic: u.configMap.forFile('users_database.yml', usersDatabase),

    configEnv: u.configMap.forEnv(self.deployment, {
      X_AUTHELIA_CONFIG_FILTERS: 'template',
    }),

    sealedJwksKey: u.sealedSecret.forFile('rsa.2048.key', secrets.jwksKey),

    sealedUserPasswords: u.sealedSecret.forEnvNamed('authelia-user-passwords', secrets.userPasswords),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.authelia),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('authelia-shared-sealed-secret', { AUTHELIA_STORAGE_POSTGRES_PASSWORD: postgresSecrets.userAuthelia }),

    ingressRoute: u.ingressRoute.from(self.service, 'auth.danielramos.me'),
  },
}
