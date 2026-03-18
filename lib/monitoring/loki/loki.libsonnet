local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local secret = k.core.v1.secret,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local configMap = k.core.v1.configMap,

  local dataVolumeName = 'data',

  local configuration = importstr './loki.config.yml',

  new():: {
    statefulSet: statefulSet.new('loki', replicas=1, containers=[
                   container.new('loki', u.image(versions.loki.image, versions.loki.version)) +
                   container.withPorts(
                     [containerPort.new('loki', 3100)]
                   ) + container.withVolumeMounts([
                     volumeMount.new(dataVolumeName, '/var/lib/loki'),
                     u.volumeMount.fromFile(self.configuration, '/etc/loki'),
                   ]) +
                   u.probes.withStartup.http('/ready', 3100),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   u.injectFile(self.configuration),
                   volume.fromHostPath(dataVolumeName, '/data/loki/data'),
                 ]) +
                 statefulSet.spec.template.spec.securityContext.withFsGroup(10001) +
                 statefulSet.spec.template.spec.securityContext.withFsGroupChangePolicy('OnRootMismatch'),

    service: k.util.serviceFor(self.statefulSet),

    configuration: u.configMap.forFile('local-config.yaml', configuration),

  },
}
