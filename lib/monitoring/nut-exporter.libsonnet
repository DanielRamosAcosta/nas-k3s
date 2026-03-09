local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

{
  local daemonSet = k.apps.v1.daemonSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new(image='ghcr.io/druggeri/nut_exporter', version):: {
    daemonSet: daemonSet.new('nut-exporter', containers=[
                 container.new('nut-exporter', u.image(image, version)) +
                 container.withArgs([
                   '--nut.username=monuser',
                 ]) +
                 container.withPorts(containerPort.new('nut', 9199)) +
                 container.withEnv(
                   u.envVars.fromSecret(self.secretEnv)
                 ),
               ]) +
               daemonSet.spec.template.spec.withHostNetwork(true) +
               daemonSet.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet'),

    service: k.util.serviceFor(self.daemonSet),

    secretEnv: u.secret.forEnv(self.daemonSet, {
      NUT_EXPORTER_PASSWORD: s.NUT_EXPORTER_PASSWORD,
    }),
  },
}
