local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local service = k.core.v1.service,
  local serviceAccount = k.core.v1.serviceAccount,
  local role = k.rbac.v1.role,
  local roleBinding = k.rbac.v1.roleBinding,

  new():: {
    serviceAccount: serviceAccount.new('mc-router'),

    role: role.new('mc-router') +
          role.withRules([
            { apiGroups: [''], resources: ['services'], verbs: ['list', 'watch'] },
            { apiGroups: ['apps'], resources: ['statefulsets'], verbs: ['list', 'watch'] },
            {
              apiGroups: ['apps'],
              resources: ['statefulsets', 'statefulsets/scale'],
              verbs: ['get', 'update', 'patch'],
              resourceNames: ['minecraft'],
            },
          ]),

    roleBinding: roleBinding.new('mc-router') +
                 roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io') +
                 roleBinding.roleRef.withKind('Role') +
                 roleBinding.roleRef.withName('mc-router') +
                 roleBinding.withSubjects([
                   { kind: 'ServiceAccount', name: 'mc-router', namespace: 'games' },
                 ]),

    deployment: deployment.new('mc-router', replicas=1, containers=[
                  container.new('mc-router', u.image(versions.mcRouter.image, versions.mcRouter.version)) +
                  container.withPorts([containerPort.new('minecraft', 25565)]) +
                  container.withArgs([
                    '--in-kube-cluster',
                    '--auto-scale-up',
                    '--auto-scale-down',
                    '--auto-scale-down-after=1h',
                    '--auto-scale-asleep-motd=Servidor dormido — conéctate para despertarlo',
                    '--auto-scale-loading-motd=Arrancando el servidor, reconéctate en unos segundos',
                  ]) +
                  container.withEnv([
                    k.core.v1.envVar.fromFieldPath('KUBE_NAMESPACE', 'metadata.namespace'),
                  ]) +
                  {
                    securityContext: {
                      runAsNonRoot: true,
                      runAsUser: 1000,
                      readOnlyRootFilesystem: true,
                      allowPrivilegeEscalation: false,
                      capabilities: { drop: ['ALL'] },
                      seccompProfile: { type: 'RuntimeDefault' },
                    },
                  } +
                  u.probes.tcp(25565),
                ]) +
                deployment.spec.template.spec.withServiceAccountName('mc-router'),

    service: k.util.serviceFor(self.deployment) +
             service.spec.withType('LoadBalancer'),
  },
}
