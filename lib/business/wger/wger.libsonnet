local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'business/wger/wger.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local nginxConfContent = importstr './wger.nginx.conf';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  local staticVolumeName = 'static',
  local mediaVolumeName = 'media',
  local beatVolumeName = 'beat',

  local commonEnv(this) =
    u.envVars.fromConfigMap(this.configEnv) +
    u.envVars.fromSealedSecret(this.sealedSecret) +
    u.envVars.fromSealedSecret(this.sealedSecretShared),

  new():: {
    local this = self,

    deployment: deployment.new('wger', replicas=1, containers=[
                  // nginx sidecar listed FIRST so service.spec.ports[0] = 80 (used by ingressRoute)
                  container.new('nginx', u.image(versions.nginx.image, versions.nginx.version)) +
                  container.withPorts([containerPort.new('http', 80)]) +
                  container.withVolumeMounts([
                    volumeMount.new(this.nginxConfig.metadata.name, '/etc/nginx/conf.d/default.conf') + volumeMount.withSubPath('default.conf') + volumeMount.withReadOnly(true),
                    volumeMount.new(staticVolumeName, '/wger/static') + volumeMount.withReadOnly(true),
                    volumeMount.new(mediaVolumeName, '/wger/media') + volumeMount.withReadOnly(true),
                  ]) +
                  u.probes.http('/', 80),

                  container.new('wger', u.image(versions.wger.image, versions.wger.version)) +
                  container.withPorts([containerPort.new('gunicorn', 8000)]) +
                  container.withEnv(commonEnv(this)) +
                  container.withVolumeMounts([
                    volumeMount.new(staticVolumeName, '/home/wger/static'),
                    volumeMount.new(mediaVolumeName, '/home/wger/media'),
                  ]) +
                  u.probes.withStartup.http('/api/v2/version/', 8000),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromEmptyDir(staticVolumeName),
                  volume.fromHostPath(mediaVolumeName, '/cold-data/wger/media'),
                  { name: this.nginxConfig.metadata.name, configMap: { name: this.nginxConfig.metadata.name } },
                ]),

    celeryWorker: deployment.new('wger-celery-worker', replicas=1, containers=[
                    container.new('celery-worker', u.image(versions.wger.image, versions.wger.version)) +
                    container.withCommand(['/start-worker']) +
                    container.withEnv(commonEnv(this)) +
                    container.withVolumeMounts([
                      volumeMount.new(mediaVolumeName, '/home/wger/media'),
                    ]),
                  ]) +
                  deployment.spec.template.spec.withVolumes([
                    volume.fromHostPath(mediaVolumeName, '/cold-data/wger/media'),
                  ]),

    celeryBeat: deployment.new('wger-celery-beat', replicas=1, containers=[
                  container.new('celery-beat', u.image(versions.wger.image, versions.wger.version)) +
                  container.withCommand(['/start-beat']) +
                  container.withEnv(commonEnv(this)) +
                  container.withVolumeMounts([
                    volumeMount.new(beatVolumeName, '/home/wger/beat'),
                  ]),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath(beatVolumeName, '/data/wger/celery-beat'),
                ]),

    service: k.util.serviceFor(self.deployment) + u.metrics(port='8000', path='/prometheus/metrics'),

    nginxConfig: u.configMap.forFile('default.conf', nginxConfContent) + { metadata+: { name: 'wger-nginx-conf' } },

    configEnv: u.configMap.forEnv(self.deployment, {
      TIME_ZONE: 'Europe/Madrid',
      TZ: 'Europe/Madrid',
      SITE_URL: 'https://gym.danielramos.me',
      CSRF_TRUSTED_ORIGINS: 'https://gym.danielramos.me',
      X_FORWARDED_PROTO_HEADER_SET: 'True',
      NUMBER_OF_PROXIES: '1',
      WGER_INSTANCE: 'https://wger.de',

      ALLOW_REGISTRATION: 'False',
      ALLOW_GUEST_USERS: 'False',

      DJANGO_DEBUG: 'False',
      DJANGO_DB_ENGINE: 'django.db.backends.postgresql',
      DJANGO_DB_HOST: 'postgres.databases.svc.cluster.local',
      DJANGO_DB_PORT: '5432',
      DJANGO_DB_NAME: 'wger',
      DJANGO_DB_USER: 'wger',
      DJANGO_PERFORM_MIGRATIONS: 'True',
      DJANGO_COLLECTSTATIC_ON_STARTUP: 'True',

      USE_CELERY: 'True',
      CELERY_WORKER_CONCURRENCY: '2',
      CELERY_BROKER: 'redis://valkey.databases.svc.cluster.local:6379/3',
      CELERY_BACKEND: 'redis://valkey.databases.svc.cluster.local:6379/4',
      DJANGO_CACHE_BACKEND: 'django_redis.cache.RedisCache',
      DJANGO_CACHE_LOCATION: 'redis://valkey.databases.svc.cluster.local:6379/2',

      SYNC_EXERCISES_CELERY: 'True',
      SYNC_EXERCISE_IMAGES_CELERY: 'False',
      SYNC_EXERCISE_VIDEOS_CELERY: 'False',
      SYNC_INGREDIENTS_CELERY: 'False',
      CACHE_API_EXERCISES_CELERY: 'False',

      EXPOSE_PROMETHEUS_METRICS: 'True',

      EMAIL_BACKEND: 'django.core.mail.backends.smtp.EmailBackend',
      EMAIL_HOST: 'smtp-relay.system.svc.cluster.local',
      EMAIL_PORT: '587',
      EMAIL_USE_TLS: 'False',
      DEFAULT_FROM_EMAIL: 'NAS <nas@mail.danielramos.me>',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.wger),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('wger-shared-sealed-secret', { DJANGO_DB_PASSWORD: postgresSecrets.userWger }),

    ingressRoute: u.ingressRoute.from(self.service, 'gym.danielramos.me'),
  },
}
