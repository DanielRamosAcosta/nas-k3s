local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/gitea/gitea.secrets.json';
local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local role = k.rbac.v1.role,
  local roleBinding = k.rbac.v1.roleBinding,
  local subject = k.rbac.v1.subject,
  local serviceAccount = k.core.v1.serviceAccount,
  local policyRule = k.rbac.v1.policyRule,

  new():: {
    statefulSet: statefulSet.new('gitea', replicas=1, containers=[
                   container.new('gitea', u.image(versions.gitea.image, versions.gitea.version)) +
                   container.withPorts([
                     containerPort.new('server', 3000),
                     containerPort.new('ssh', 2222),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSealedSecret(self.sealed_secret) +
                     u.envVars.fromSealedSecret(self.sealed_secret_shared),
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('data', '/data'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromHostPath('data', '/cold-data/gitea/data') + volume.hostPath.withType('DirectoryOrCreate'),
                 ]) +
                 statefulSet.spec.template.spec.withServiceAccount('git-ssh'),

    service: k.util.serviceFor(self.statefulSet) + u.prometheus(port='3000', path='/metrics'),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      // database
      GITEA__database__DB_TYPE: 'postgres',
      GITEA__database__HOST: 'postgres.databases.svc.cluster.local:5432',
      GITEA__database__NAME: 'gitea',
      GITEA__database__USER: 'gitea',

      // mailer
      GITEA__mailer__ENABLED: 'true',
      GITEA__mailer__FROM: 'NAS <nas@mail.danielramos.me>',
      GITEA__mailer__PROTOCOL: 'smtps',
      GITEA__mailer__SMTP_ADDR: 'smtp.eu.mailgun.org',
      GITEA__mailer__SMTP_PORT: '587',
      GITEA__mailer__USER: 'nas@mail.danielramos.me',

      // metrics
      GITEA__metrics__ENABLED: 'true',

      // openid
      GITEA__openid__ENABLE_OPENID_SIGNIN: 'false',
      GITEA__openid__ENABLE_OPENID_SIGNUP: 'true',
      GITEA__openid__WHITELISTED_URIS: 'auth.danielramos.me',

      // service
      GITEA__service__DISABLE_REGISTRATION: 'false',
      GITEA__service__ALLOW_ONLY_EXTERNAL_REGISTRATION: 'true',
      GITEA__service__SHOW_REGISTRATION_BUTTON: 'false',
      GITEA__service__ENABLE_PASSWORD_SIGNIN_FORM: 'false',

      // server
      GITEA__server__DOMAIN: 'git.danielramos.me',
      GITEA__server__SSH_DOMAIN: 'ssh.danielramos.me',
      GITEA__server__SSH_PORT: '22',
      GITEA__server__SSH_LISTEN_PORT: '2222',
      GITEA__server__START_SSH_SERVER: 'true',
    }),

    sealed_secret: u.sealedSecret.forEnv(self.statefulSet, secrets.gitea),
    sealed_secret_shared: u.sealedSecret.wide.forEnvNamed('gitea-shared-sealed-secret', secrets.shared),

    ingressRoute: u.ingressRoute.from(self.service, {
      '3000': 'git.danielramos.me',
    }),

    rbac: {
      service_account:
        serviceAccount.new('git-ssh'),

      role:
        role.new() +
        role.mixin.metadata.withName('git-ssh-exec') +
        role.withRules([
          policyRule.withApiGroups(['']) +
          policyRule.withResources(['pods']) +
          policyRule.withResourceNames(['gitea-0']) +
          policyRule.withVerbs(['get', 'list']),
          policyRule.withApiGroups(['']) +
          policyRule.withResources(['pods/exec']) +
          policyRule.withResourceNames(['gitea-0']) +
          policyRule.withVerbs(['create']),
        ]),

      role_binding:
        roleBinding.new() +
        roleBinding.mixin.metadata.withName('git-ssh-exec-binding') +
        roleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        roleBinding.mixin.roleRef.withKind('Role') +
        roleBinding.mixin.roleRef.withName('git-ssh-exec') +
        roleBinding.withSubjects([
          subject.new() +
          subject.withKind('ServiceAccount') +
          subject.withName('git-ssh') +
          subject.withNamespace('media'),
        ]),
    },
  },
}
