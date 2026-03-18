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
  local policyRule = k.rbac.v1.policyRule,

  local dataVolumeName = 'data',

  local configuration = importstr './prometheus.yml',

  new():: {
    statefulSet: statefulSet.new('prometheus', replicas=1, containers=[
                   container.new('prometheus', u.image(versions.prometheus.image, versions.prometheus.version)) +
                   container.withPorts(
                     [containerPort.new('prometheus', 9090)]
                   ) + container.withVolumeMounts([
                     volumeMount.new(dataVolumeName, '/prometheus'),
                     u.volumeMount.fromFile(self.configuration, '/etc/prometheus'),
                   ]) +
                   u.probes.withStartup.http('/-/ready', 9090),
                 ]) +
                 statefulSet.spec.template.spec.withServiceAccount('prometheus') +
                 statefulSet.spec.template.spec.withVolumes([
                   u.injectFile(self.configuration),
                   volume.fromHostPath(dataVolumeName, '/data/prometheus/data'),
                 ]) +
                 statefulSet.spec.template.spec.securityContext.withFsGroup(65534) +
                 statefulSet.spec.template.spec.securityContext.withFsGroupChangePolicy('OnRootMismatch'),

    service: k.util.serviceFor(self.statefulSet),

    configuration: u.configMap.forFile('prometheus.yml', configuration),

    rbac: u.rbac('prometheus', 'monitoring', rules=[
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods']) +
      policyRule.withVerbs(['get', 'watch', 'list']),
      policyRule.withNonResourceURLs('/metrics') +
      policyRule.withVerbs(['get']),
    ]),
  },
}
