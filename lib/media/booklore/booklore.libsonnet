local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/booklore/booklore.secrets.json';
local logbackConfig = importstr './booklore.logback-spring.xml';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('booklore', replicas=1, containers=[
      container.new('booklore', u.image(versions.booklore.image, versions.booklore.version)) +
      container.withPorts([containerPort.new('server', 6060)]) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealed_secret),
      ) +
      container.withVolumeMounts([
        volumeMount.new('data', '/app/data'),
        volumeMount.new('books', '/books'),
        volumeMount.new('bookdrop', '/bookdrop'),
        u.volumeMount.fromFile(self.logbackConfiguration, '/config'),
      ]) +
      u.probes.withStartup.http('/api/v1/healthcheck', 6060) +
      { startupProbe+: { failureThreshold: 60 } },
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromHostPath('data', '/cold-data/booklore/data'),
      volume.fromHostPath('books', '/cold-data/booklore/books'),
      volume.fromHostPath('bookdrop', '/cold-data/booklore/bookdrop'),
      u.injectFile(self.logbackConfiguration),
    ]),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      USER_ID: '0',
      GROUP_ID: '0',
      TZ: 'Atlantic/Canary',
      BOOKLORE_PORT: '6060',
      DATABASE_URL: 'jdbc:mariadb://mariadb.databases.svc.cluster.local:3306/booklore',
      DATABASE_USERNAME: 'booklore',
      LOGGING_CONFIG: '/config/logback-spring.xml',
      SPRINGDOC_API_DOCS_ENABLED: 'false',
      SPRINGDOC_SWAGGER_UI_ENABLED: 'false',
    }),

    sealed_secret: u.sealedSecret.wide.forEnvNamed('booklore-shared-sealed-secret', secrets.shared),

    logbackConfiguration: u.configMap.forFile('logback-spring.xml', logbackConfig),

    ingressRoute: u.ingressRoute.from(self.service, 'books.danielramos.me'),
  },
}
