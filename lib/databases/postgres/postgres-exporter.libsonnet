local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  local queriesDir = '/etc/postgres-exporter',
  local queriesFile = 'postgres-queries.yml',

  local queries = importstr './postgres-queries.yml',

  new():: {
    deployment: deployment.new('postgres-exporter', replicas=1, containers=[
      container.new('postgres-exporter', u.image(versions.postgresExporter.image, versions.postgresExporter.version)) +
      container.withPorts(containerPort.new('metrics', 9187)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      container.withVolumeMounts([
        u.volumeMount.fromFile(self.queriesConfigMap, queriesDir),
      ]) +
      u.probes.http('/', 9187),
    ]) + deployment.spec.template.spec.withVolumes([
      u.volume.fromConfigMap(self.queriesConfigMap),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('9187'),

    configEnv: u.configMap.forEnv(self.deployment, {
      DATA_SOURCE_URI: 'postgres.databases.svc.cluster.local:5432/monitoring?sslmode=disable',
      DATA_SOURCE_USER: 'monitoring',
      // Flag deprecado pero vigente en v0.20.1 para las custom queries SQL.
      PG_EXPORTER_EXTEND_QUERY_PATH: queriesDir + '/' + queriesFile,
    }),

    queriesConfigMap: u.configMap.forFile(queriesFile, queries),

    sealedSecret: u.sealedSecret.forEnvNamed('postgres-exporter-sealed-secret', secrets.monitoringExporter),
  },
}
