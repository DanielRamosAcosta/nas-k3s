local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local u = import 'utils.libsonnet';

{
  local daemonSet = k.apps.v1.daemonSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new(image='quay.io/prometheus/node-exporter', version):: {
    daemonSet: daemonSet.new('node-exporter', containers=[
                 container.new('node-exporter', u.image(image, version)) +
                 container.withArgs([
                   '--path.rootfs=/host',
                   '--path.procfs=/host/proc',
                   '--path.sysfs=/host/sys',
                   '--collector.netdev',
                   '--collector.netstat',
                   '--collector.netclass',
                 ]) +
                 container.withPorts(
                   [containerPort.new('node-exporter', 9100)]
                 ) + container.withVolumeMounts([
                   volumeMount.new('root', '/host', true),
                   volumeMount.new('proc', '/host/proc', true),
                   volumeMount.new('sys', '/host/sys', true),
                 ]),
               ]) +
               daemonSet.spec.template.spec.withVolumes([
                 volume.fromHostPath('root', '/') + volume.hostPath.withType('Directory'),
                 volume.fromHostPath('proc', '/proc') + volume.hostPath.withType('Directory'),
                 volume.fromHostPath('sys', '/sys') + volume.hostPath.withType('Directory'),
               ]) +
               daemonSet.spec.template.spec.withHostPID(true) +
               daemonSet.spec.template.spec.withHostNetwork(true),

    service: k.util.serviceFor(self.daemonSet) + u.prometheus('9100'),
  },
}
