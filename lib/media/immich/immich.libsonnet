local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/immich/immich.secrets.json';

local immichConfig = importstr './immich.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local deployment = k.apps.v1.deployment,
  local service = k.core.v1.service,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('immich', replicas=1, containers=[
                   container.new('immich', u.image(versions.immich.image, versions.immich.version)) +
                   container.withPorts(
                     [containerPort.new('server', 2283)]
                   ) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSealedSecret(self.sealedSecretShared),
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('upload', '/usr/src/app/upload'),
                     volumeMount.new('merged-config', '/app/config') + volumeMount.withReadOnly(true),
                   ]) +
                   u.probes.withStartup.http('/api/server/ping', 2283),
                 ]) +
                 statefulSet.spec.template.spec.withInitContainers(
                   container.new('render-config', u.image(versions.envsubst.image, versions.envsubst.version)) +
                   container.withCommand(['sh', '-c', 'envsubst < /data/config.json > /output/immich.json']) +
                   container.withEnv(
                     u.envVars.fromSealedSecret(self.sealedSecret),
                   ) +
                   container.withVolumeMounts([
                     u.volumeMount.fromFile(self.immichConfigPublic, '/data'),
                     volumeMount.new('merged-config', '/output'),
                   ])
                 ) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromHostPath('upload', '/cold-data/immich/upload'),
                   u.volume.fromConfigMap(self.immichConfigPublic),
                   volume.fromEmptyDir('merged-config'),
                 ]),

    service: k.util.serviceFor(self.statefulSet) + u.prometheus(port='8081'),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      DB_HOSTNAME: 'postgres.databases.svc.cluster.local',
      DB_USERNAME: 'immich',
      REDIS_HOSTNAME: 'valkey.databases.svc.cluster.local',
      IMMICH_CONFIG_FILE: '/app/config/immich.json',
      IMMICH_TELEMETRY_INCLUDE: 'all',
      IMMICH_LOG_FORMAT: 'json',
      IMMICH_PORT: '2283',
    }),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('immich-shared-sealed-secret', {
      DB_PASSWORD: postgresSecrets.userImmich,
    }),

    sealedSecret: u.sealedSecret.forEnv(self.statefulSet, secrets.immich),

    immichConfigPublic: u.configMap.forFile('config.json', immichConfig),

    ingressRoute: u.ingressRoute.from(self.service, 'photos.danielramos.me'),

    // Machine Learning Service
    mlDeployment: deployment.new('immich-machine-learning', replicas=1, containers=[
                    container.new('immich-machine-learning', u.image(versions.immichMl.image, versions.immichMl.version)) +
                    container.withPorts([
                      containerPort.new('http', 3003),
                    ]) +
                    container.withEnv(
                      u.envVars.fromConfigMap(self.mlConfigEnv),
                    ) +
                    container.withVolumeMounts([
                      volumeMount.new('model-cache', '/cache'),
                    ]) +
                    {
                      resources: {
                        requests: {
                          memory: '2Gi',
                          cpu: '1000m',
                        },
                        limits: {
                          memory: '6Gi',
                          cpu: '4000m',
                        },
                      },
                    } +
                    u.probes.withStartup.http('/ping', 3003),
                  ]) +
                  deployment.spec.template.spec.withVolumes([
                    volume.fromHostPath('model-cache', '/data/immich/ml-cache'),
                  ]) +
                  deployment.spec.template.spec.withEnableServiceLinks(false) +
                  deployment.spec.strategy.withType('Recreate'),

    mlConfigEnv: u.configMap.forEnv(self.mlDeployment, {
      TRANSFORMERS_CACHE: '/cache',
      PYTHONUNBUFFERED: '1',
    }),

    mlService: k.util.serviceFor(self.mlDeployment),

  },
}
