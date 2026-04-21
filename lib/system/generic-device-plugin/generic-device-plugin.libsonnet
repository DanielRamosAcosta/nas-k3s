local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local daemonSet = k.apps.v1.daemonSet,
  local container = k.core.v1.container,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    daemonSet: daemonSet.new('generic-device-plugin', containers=[
                 container.new('generic-device-plugin', u.image(versions.genericDevicePlugin.image, versions.genericDevicePlugin.version)) +
                 container.withArgs([
                   '--device',
                   std.manifestYamlDoc({
                     name: 'dri',
                     groups: [{
                       count: 10,
                       paths: [{ path: '/dev/dri/renderD128' }],
                     }],
                   }),
                 ]) +
                 container.withVolumeMounts([
                   volumeMount.new('device-plugin', '/var/lib/kubelet/device-plugins'),
                   volumeMount.new('dev', '/dev'),
                 ]) +
                 container.securityContext.withPrivileged(true),
               ]) +
               daemonSet.spec.template.spec.withVolumes([
                 volume.fromHostPath('device-plugin', '/var/lib/kubelet/device-plugins') + volume.hostPath.withType('Directory'),
                 volume.fromHostPath('dev', '/dev') + volume.hostPath.withType('Directory'),
               ]),
  },
}
