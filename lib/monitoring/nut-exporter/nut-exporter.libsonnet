local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'monitoring/nut-exporter/nut-exporter.secrets.json';

{
  local daemonSet = k.apps.v1.daemonSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    daemonSet: daemonSet.new('nut-exporter', containers=[
                 container.new('nut-exporter', u.image(versions.nutExporter.image, versions.nutExporter.version)) +
                 container.withArgs([
                   '--nut.username=monuser',
                 ]) +
                 container.withPorts(containerPort.new('nut', 9199)) +
                 container.withEnv(
                   u.envVars.fromSealedSecret(self.sealed_secret)
                 ),
               ]) +
               daemonSet.spec.template.spec.withHostNetwork(true) +
               daemonSet.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet'),

    service: k.util.serviceFor(self.daemonSet),

    sealed_secret: u.sealedSecret.forEnv(self.daemonSet, secrets.nutExporter),
  },
}
