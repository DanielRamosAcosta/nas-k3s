local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

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

  new(image='docker.io/prom/prometheus', version):: {
    statefulSet: statefulSet.new('prometheus', replicas=1, containers=[
                   container.new('prometheus', u.image(image, version)) +
                   container.withPorts(
                     [containerPort.new('prometheus', 9090)]
                   ) + container.withVolumeMounts([
                     volumeMount.new(dataVolumeName, '/prometheus'),
                     u.volumeMount.fromFile(self.configuration, '/etc/prometheus'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withServiceAccount('prometheus') +
                 statefulSet.spec.template.spec.withVolumes([
                   u.injectFile(self.configuration),
                   volume.fromPersistentVolumeClaim(dataVolumeName, self.pvc.metadata.name),
                 ]) +
                 statefulSet.spec.template.spec.securityContext.withFsGroup(65534) +
                 statefulSet.spec.template.spec.securityContext.withFsGroupChangePolicy('OnRootMismatch'),

    service: k.util.serviceFor(self.statefulSet),

    configuration: u.configMap.forFile('prometheus.yml', configuration),

    pv: u.pv.localPathFor(self.statefulSet, '50Gi', '/data/prometheus/data'),
    pvc: u.pvc.from(self.pv),

    rbac: u.rbac('prometheus', 'monitoring', rules=[
      policyRule.withApiGroups(['']) +
      policyRule.withResources(['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods']) +
      policyRule.withVerbs(['get', 'watch', 'list']),
      policyRule.withNonResourceURLs('/metrics') +
      policyRule.withVerbs(['get']),
    ]),
  },
}
