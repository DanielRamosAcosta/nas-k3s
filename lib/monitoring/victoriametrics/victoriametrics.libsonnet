local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local policyRule = k.rbac.v1.policyRule,

  local dataVolumeName = 'data',

  local configuration = importstr './victoriametrics.yml',

  new():: {
    statefulSet: statefulSet.new('victoriametrics', replicas=1, containers=[
                   container.new('victoriametrics', u.image(versions.victoriametrics.image, versions.victoriametrics.version)) +
                   container.withArgs([
                     '-promscrape.config=/etc/victoriametrics/victoriametrics.yml',
                     '-storageDataPath=/victoria-metrics-data',
                     '-retentionPeriod=100y',
                   ]) +
                   container.withPorts([
                     containerPort.new('http', 8428),
                   ]) +
                   container.withVolumeMounts([
                     volumeMount.new(dataVolumeName, '/victoria-metrics-data'),
                     u.volumeMount.fromFile(self.configuration, '/etc/victoriametrics'),
                   ]) +
                   u.probes.withStartup.http('/-/healthy', 8428),
                 ]) +
                 statefulSet.spec.template.spec.withServiceAccount('victoriametrics') +
                 statefulSet.spec.template.spec.withVolumes([
                   u.injectFile(self.configuration),
                   volume.fromHostPath(dataVolumeName, '/data/victoriametrics/data'),
                 ]),

    service: k.util.serviceFor(self.statefulSet),

    configuration: u.configMap.forFile('victoriametrics.yml', configuration),

    rbac: u.rbac('victoriametrics', 'monitoring', rules=[
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods']) +
      policyRule.withVerbs(['get', 'watch', 'list']),
      policyRule.withNonResourceURLs('/metrics') +
      policyRule.withVerbs(['get']),
    ]),
  },
}
