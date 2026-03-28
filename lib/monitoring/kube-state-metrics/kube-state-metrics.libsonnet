local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local policyRule = k.rbac.v1.policyRule,
  local name = 'kube-state-metrics',

  local rule(group, resources, verbs) =
    policyRule.withApiGroups([group]) +
    policyRule.withResources(resources) +
    policyRule.withVerbs(verbs),

  local watch(group, resources) = rule(group, resources, ['list', 'watch']),
  local create(group, resources) = rule(group, resources, ['create']),

  new():: {
    local rbac = u.rbac(name, 'monitoring', [
      watch('', [
        'configmaps',
        'secrets',
        'nodes',
        'pods',
        'services',
        'serviceaccounts',
        'resourcequotas',
        'replicationcontrollers',
        'limitranges',
        'persistentvolumeclaims',
        'persistentvolumes',
        'namespaces',
        'endpoints',
      ]),
      watch('apps', ['statefulsets', 'daemonsets', 'deployments', 'replicasets']),
      watch('batch', ['cronjobs', 'jobs']),
      watch('autoscaling', ['horizontalpodautoscalers']),
      watch('policy', ['poddisruptionbudgets']),
      watch('certificates.k8s.io', ['certificatesigningrequests']),
      watch('storage.k8s.io', ['storageclasses', 'volumeattachments']),
      watch('admissionregistration.k8s.io', ['mutatingwebhookconfigurations', 'validatingwebhookconfigurations']),
      watch('networking.k8s.io', ['networkpolicies', 'ingresses']),
      watch('coordination.k8s.io', ['leases']),
      watch('rbac.authorization.k8s.io', ['clusterrolebindings', 'clusterroles', 'rolebindings', 'roles']),

      create('authentication.k8s.io', ['tokenreviews']),
      create('authorization.k8s.io', ['subjectaccessreviews']),
    ]),

    service_account: rbac.service_account,
    cluster_role: rbac.cluster_role,
    cluster_role_binding: rbac.cluster_role_binding,

    deployment: deployment.new(name, replicas=1, containers=[
                  container.new(name, u.image(versions.kubeStateMetrics.image, versions.kubeStateMetrics.version)) +
                  container.withPorts([
                    containerPort.new('http-metrics', 8080),
                  ]) +
                  u.probes.http('/healthz', 8080),
                ]) +
                deployment.spec.template.spec.withServiceAccountName(name) +
                deployment.spec.template.spec.withAutomountServiceAccountToken(true),

    service: k.util.serviceFor(self.deployment) + u.metrics('8080'),
  },
}
