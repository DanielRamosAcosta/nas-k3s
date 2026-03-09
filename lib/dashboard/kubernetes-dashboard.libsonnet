local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

local helm = tanka.helm.new(std.thisFile);
local serviceAccount = k.core.v1.serviceAccount;
local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;
local subject = k.rbac.v1.subject;

{
  new():: helm.template('kubernetes-dashboard', '../../charts/kubernetes-dashboard', {
    namespace: 'dashboard',
  }),

  createAdmin():: {
    adminSa: serviceAccount.new('admin-user'),

    adminCrb: clusterRoleBinding.new('admin-user') +
              clusterRoleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io') +
              clusterRoleBinding.roleRef.withKind('ClusterRole') +
              clusterRoleBinding.roleRef.withName('cluster-admin') +
              clusterRoleBinding.withSubjects([
                subject.withKind('ServiceAccount') +
                subject.withName('admin-user') +
                subject.withNamespace('dashboard'),
              ]),
  },
}
