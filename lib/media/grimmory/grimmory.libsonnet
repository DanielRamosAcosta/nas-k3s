local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/grimmory/grimmory.secrets.json';
local logbackConfig = importstr './grimmory.logback-spring.xml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('grimmory', replicas=0, containers=[
      container.new('grimmory', u.image(versions.grimmory.image, versions.grimmory.version)) +
      container.withPorts([containerPort.new('server', 6060)]) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      container.withVolumeMounts([
        volumeMount.new('data', '/app/data'),
        volumeMount.new('books', '/books'),
        volumeMount.new('bookdrop', '/bookdrop'),
        u.volumeMount.fromFile(self.logbackConfiguration, '/config'),
      ]) +
      u.probes.withStartup.http('/api/v1/healthcheck', 6060) +
      { startupProbe+: { failureThreshold: 60 } },
    ]) + deployment.spec.template.spec.withVolumes([
      volume.fromHostPath('data', '/cold-data/grimmory/data'),
      volume.fromHostPath('books', '/cold-data/grimmory/books'),
      volume.fromHostPath('bookdrop', '/cold-data/grimmory/bookdrop'),
      u.injectFile(self.logbackConfiguration),
    ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      USER_ID: '0',
      GROUP_ID: '0',
      TZ: 'Atlantic/Canary',
      DATABASE_URL: 'jdbc:mariadb://mariadb.databases.svc.cluster.local:3306/grimmory',
      DATABASE_USERNAME: 'grimmory',
      LOGGING_CONFIG: '/config/logback-spring.xml',
    }),

    sealedSecret: u.sealedSecret.wide.forEnvNamed('grimmory-shared-sealed-secret', secrets.shared),

    logbackConfiguration: u.configMap.forFile('logback-spring.xml', logbackConfig),

    ingressRoute: u.ingressRoute.from(self.service, 'books.danielramos.me'),
  },
}
