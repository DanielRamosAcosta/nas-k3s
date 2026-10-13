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
  local job = k.batch.v1.job,

  // Provisiona el SocialApp de allauth (fila en Postgres, fuera de git) de forma idempotente.
  // update_or_create keyed en provider+provider_id; sites.add tolera re-ejecución. Se invoca
  // via manage.py shell -c, que lee los settings Django directamente de env vars (no depende
  // del entrypoint de la imagen).
  local provisionOidcSnippet = |||
    import os
    from allauth.socialaccount.models import SocialApp, SocialAccount
    from django.contrib.sites.models import Site
    from django.contrib.auth import get_user_model
    app, _ = SocialApp.objects.update_or_create(
        provider='openid_connect', provider_id='authelia',
        defaults=dict(name='Authelia',
                      client_id=os.environ['OIDC_CLIENT_ID'],
                      secret=os.environ['OIDC_CLIENT_SECRET'],
                      settings={'server_url': 'https://auth.danielramos.me'}))
    app.sites.add(Site.objects.get(id=1))
    username = os.environ.get('OIDC_BOOTSTRAP_USERNAME')
    subject = os.environ.get('OIDC_BOOTSTRAP_SUBJECT')
    if username and subject:
        user = get_user_model().objects.filter(username=username).first()
        if user:
            SocialAccount.objects.update_or_create(
                provider='authelia', uid=subject, defaults=dict(user=user))
  |||,

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
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

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
                  ]) +
                  deployment.spec.template.spec.withEnableServiceLinks(false),

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
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    provisionOidcJob: job.new('wger-provision-oidc') +
                      job.metadata.withAnnotationsMixin({
                        'argocd.argoproj.io/hook': 'PostSync',
                        'argocd.argoproj.io/hook-delete-policy': 'BeforeHookCreation',
                      }) +
                      job.spec.template.spec.withRestartPolicy('OnFailure') +
                      job.spec.template.spec.withEnableServiceLinks(false) +
                      job.spec.template.spec.withContainers([
                        container.new('provision-oidc', u.image(versions.wger.image, versions.wger.version)) +
                        container.withWorkingDir('/home/wger/src') +
                        container.withCommand(['python3', 'manage.py', 'shell', '-c', provisionOidcSnippet]) +
                        container.withEnv(commonEnv(this)),
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
      DJANGO_DB_DATABASE: 'wger',
      DJANGO_DB_USER: 'wger',
      DJANGO_PERFORM_MIGRATIONS: 'True',
      DJANGO_COLLECTSTATIC_ON_STARTUP: 'True',
      WGER_USE_GUNICORN: 'True',

      USE_CELERY: 'True',
      CELERY_WORKER_CONCURRENCY: '2',
      CELERY_BROKER: 'redis://valkey.databases.svc.cluster.local:6379/3',
      CELERY_BACKEND: 'redis://valkey.databases.svc.cluster.local:6379/4',
      DJANGO_CACHE_BACKEND: 'django_redis.cache.RedisCache',
      DJANGO_CACHE_LOCATION: 'redis://valkey.databases.svc.cluster.local:6379/2',
      DJANGO_CACHE_CLIENT_CLASS: 'django_redis.client.DefaultClient',

      SYNC_EXERCISES_CELERY: 'True',
      SYNC_EXERCISE_IMAGES_CELERY: 'False',
      SYNC_EXERCISE_VIDEOS_CELERY: 'False',
      SYNC_INGREDIENTS_CELERY: 'False',
      CACHE_API_EXERCISES_CELERY: 'False',

      EXPOSE_PROMETHEUS_METRICS: 'True',

      // OIDC nativo vía django-allauth (proveedor genérico openid_connect contra Authelia).
      // client_id legible en claro; client_secret llega vía sealedSecret. El registro SocialApp
      // (fila en Postgres) lo provisiona el Job 'wger-provision-oidc' (hook PostSync de ArgoCD).
      WGER_SOCIAL_PROVIDERS: 'openid_connect',
      OIDC_CLIENT_ID: 'wger',

      // Pre-enlace de la cuenta local existente (creada antaño por el forward-auth) a su
      // identidad OIDC. Con ALLOW_REGISTRATION=False el signup social está cerrado, así que sin
      // este SocialAccount el primer login OIDC se rechazaría. El 'subject' es el identificador
      // opaco estable que Authelia asigna a este usuario (no es secreto; viaja en el id_token).
      // Lo aplica el mismo Job 'wger-provision-oidc' de forma idempotente.
      OIDC_BOOTSTRAP_USERNAME: 'dani',
      OIDC_BOOTSTRAP_SUBJECT: '0a50e2cb-cbb7-4e8c-bf73-293049f3e2e6',

      ENABLE_EMAIL: 'True',
      EMAIL_HOST: 'smtp-relay.system.svc.cluster.local',
      EMAIL_PORT: '587',
      EMAIL_HOST_USER: '',
      EMAIL_HOST_PASSWORD: '',
      EMAIL_USE_TLS: 'False',
      FROM_EMAIL: 'NAS <nas@mail.danielramos.me>',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.wger),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('wger-shared-sealed-secret', { DJANGO_DB_PASSWORD: postgresSecrets.userWger }),

    // Login vía OIDC nativo (allauth) — sin forward-auth de Traefik. Ruta plana: ni la raíz ni
    // /api llevan auth de Traefik (wger gestiona su propia sesión; /api sigue usando tokens
    // propios de wger).
    ingressRoute: u.ingressRoute.from(self.service, 'gym.danielramos.me'),
  },
}
