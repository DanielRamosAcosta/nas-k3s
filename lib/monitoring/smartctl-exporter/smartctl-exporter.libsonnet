local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';

{
  local daemonSet = k.apps.v1.daemonSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    daemonSet: daemonSet.new('smartctl-exporter', containers=[
                 container.new('smartctl-exporter', u.image(versions.smartctlExporter.image, versions.smartctlExporter.version)) +
                 container.withPorts(containerPort.new('smartctl', 9633)) +
                 container.securityContext.withPrivileged(true) +
                 container.securityContext.withRunAsUser(0) +
                 container.securityContext.withRunAsGroup(0) +
                 container.securityContext.withReadOnlyRootFilesystem(true) +
                 container.withVolumeMounts([
                   volumeMount.new('dev', '/dev'),
                   volumeMount.new('run-udev', '/run/udev', true),
                 ]),
               ]) +
               daemonSet.spec.template.spec.withVolumes([
                 volume.fromHostPath('dev', '/dev') + volume.hostPath.withType('Directory'),
                 volume.fromHostPath('run-udev', '/run/udev') + volume.hostPath.withType('Directory'),
               ]),

    service: k.util.serviceFor(self.daemonSet) + u.prometheus('9633'),
  },
}
