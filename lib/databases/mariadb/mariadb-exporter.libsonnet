local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'databases/mariadb/mariadb.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  local myCnfPath = '/etc/mysqld-exporter/my.cnf',

  new():: {
    deployment: deployment.new('mysqld-exporter', replicas=1, containers=[
      container.new('mysqld-exporter', u.image(versions.mysqldExporter.image, versions.mysqldExporter.version)) +
      container.withArgs(['--config.my-cnf=' + myCnfPath]) +
      container.withPorts(containerPort.new('metrics', 9104)) +
      container.withVolumeMounts([
        u.volumeMount.fromSealedSecretFile(self.myCnfSecret, '/etc/mysqld-exporter'),
      ]) +
      u.probes.http('/', 9104),
    ]) + deployment.spec.template.spec.withVolumes([
      // 0644 — el exporter corre como usuario non-root y el fichero lo crea root,
      // así que debe ser legible por el grupo/otros para poder abrirlo.
      u.volume.fromSealedSecret(self.myCnfSecret) +
      { secret+: { defaultMode: std.parseOctal('0644') } },
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('9104'),

    myCnfSecret: u.sealedSecret.forFile('my.cnf', secrets.monitoringMycnf['my.cnf']),
  },
}
