local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

local sftpgoConfig = importstr './sftpgo.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local secret = k.core.v1.secret,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local configMap = k.core.v1.configMap,

  new():: {
    statefulSet: statefulSet.new('sftpgo', replicas=1, containers=[
                   container.new('sftpgo', u.image(versions.sftpgo.image, versions.sftpgo.version)) +
                   container.withPorts([
                     containerPort.new('server', 8080),
                     containerPort.new('metrics', 9219),
                   ]) +
                   container.withEnv(
                     u.envVars.fromSecret(self.secretsEnv),
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('data', '/srv/sftpgo'),
                     u.volumeMount.fromFile(self.configuration, '/etc/sftpgo'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.securityContext.withRunAsUser(0) +
                 statefulSet.spec.template.spec.securityContext.withRunAsGroup(0) +
                 statefulSet.spec.template.spec.securityContext.withFsGroup(0) +
                 statefulSet.spec.template.spec.withVolumes([
                   u.injectFile(self.configuration),
                   volume.fromPersistentVolumeClaim('data', self.pvc.metadata.name),
                 ]),

    service: k.util.serviceFor(self.statefulSet) + u.prometheus(port='9219', path='/metrics'),

    configuration: u.configMap.forFile('sftpgo.json', sftpgoConfig),

    secretsEnv: u.secret.forEnv(self.statefulSet, {
      SFTPGO_DATA_PROVIDER__PASSWORD: s.POSTGRES_PASSWORD_SFTPGO,
      SFTPGO_HTTPD__BINDINGS__0__OIDC__CLIENT_ID: s.AUTHELIA_OIDC_SFTPGO_CLIENT_ID,
      SFTPGO_HTTPD__BINDINGS__0__OIDC__CLIENT_SECRET: s.AUTHELIA_OIDC_SFTPGO_CLIENT_SECRET,
    }),

    pv: u.pv.localPathFor(self.statefulSet, '40Gi', '/cold-data/sftpgo/data'),
    pvc: u.pvc.from(self.pv),

    ingressRoute: u.ingressRoute.from(self.service, {
      '8080': 'cloud.danielramos.me',
    }),
  },
}
