local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

local immichConfig = importstr './immich.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local deployment = k.apps.v1.deployment,
  local service = k.core.v1.service,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local secret = k.core.v1.secret,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local configMap = k.core.v1.configMap,

  new(image='ghcr.io/immich-app/immich-server', version, mlImage='ghcr.io/immich-app/immich-machine-learning'):: {
    statefulSet: statefulSet.new('immich', replicas=1, containers=[
                   container.new('immich', u.image(image, version)) +
                   container.withPorts(
                     [containerPort.new('server', 2283)]
                   ) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSecret(self.secretsEnv),
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('upload', '/usr/src/app/upload'),
                     volumeMount.new('merged-config', '/app/config') + volumeMount.withReadOnly(true),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withInitContainers(
                   container.new('merge-config', u.image('ghcr.io/danielramosacosta/jq', 'main-5231ab6')) +
                   u.command.jq.merge('/data/config.json', '/data/config-secret.json', '/output/immich.json') +
                   container.withVolumeMounts([
                     u.volumeMount.fromFile(self.immichConfigPublic, '/data'),
                     u.volumeMount.fromFile(self.immichConfigSecret, '/data'),
                     volumeMount.new('merged-config', '/output'),
                   ])
                 ) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromPersistentVolumeClaim('upload', self.pvc.metadata.name),
                   u.volume.fromConfigMap(self.immichConfigPublic),
                   u.volume.fromSecret(self.immichConfigSecret),
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

    secretsEnv: u.secret.forEnv(self.statefulSet, {
      DB_PASSWORD: s.POSTGRES_PASSWORD_IMMICH,
    }),

    immichConfigPublic: u.configMap.forFile('config.json', immichConfig),

    immichConfigSecret: u.secret.forFile('config-secret.json', u.jsonStringify({
      oauth: {
        clientId: s.AUTHELIA_OIDC_IMMICH_CLIENT_ID,
        clientSecret: s.AUTHELIA_OIDC_IMMICH_CLIENT_SECRET,
      },
      notifications: {
        smtp: {
          transport: {
            password: s.SMTP_PASSWORD,
          },
        },
      },
    })),

    pv: u.pv.localPathFor(self.statefulSet, '40Gi', '/cold-data/immich/upload'),
    pvc: u.pvc.from(self.pv),

    ingressRoute: u.ingressRoute.from(self.service, 'photos.danielramos.me'),

    // Machine Learning Service
    mlDeployment: deployment.new('immich-machine-learning', replicas=1, containers=[
                    container.new('immich-machine-learning', u.image(mlImage, version)) +
                    container.withPorts([
                      containerPort.new('http', 3003),
                    ]) +
                    container.withEnv([
                      k.core.v1.envVar.new('TRANSFORMERS_CACHE', '/cache'),
                      k.core.v1.envVar.new('PYTHONUNBUFFERED', '1'),
                    ]) +
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
                    },
                  ]) +
                  deployment.spec.template.spec.withVolumes([
                    volume.fromPersistentVolumeClaim('model-cache', self.mlPvc.metadata.name),
                  ]) +
                  deployment.spec.template.spec.withEnableServiceLinks(false) +
                  deployment.spec.strategy.withType('Recreate'),

    mlService: k.util.serviceFor(self.mlDeployment),

    mlPv: u.pv.localPathFor(self.mlDeployment, '15Gi', '/data/immich/ml-cache'),
    mlPvc: u.pvc.from(self.mlPv),
  },
}
