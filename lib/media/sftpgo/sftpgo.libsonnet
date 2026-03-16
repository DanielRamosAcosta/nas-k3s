local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/sftpgo/sftpgo.secrets.json';

local sftpgoConfig = importstr './sftpgo.config.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('sftpgo', replicas=1, containers=[
                   container.new('sftpgo', u.image(versions.sftpgo.image, versions.sftpgo.version)) +
                   container.withPorts([
                     containerPort.new('server', 8080),
                     containerPort.new('metrics', 9219),
                   ]) +
                   container.withEnv(
                     u.envVars.fromSealedSecret(self.sealed_secret) +
                     u.envVars.fromSealedSecret(self.sealed_secret_shared),
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

    sealed_secret: u.sealedSecret.forEnv(self.statefulSet, secrets.sftpgo),
    sealed_secret_shared: u.sealedSecret.wide.forEnvNamed('sftpgo-shared-sealed-secret', secrets.shared),

    pv: u.pv.localPathFor(self.statefulSet, '40Gi', '/cold-data/sftpgo/data'),
    pvc: u.pvc.from(self.pv),

    ingressRoute: u.ingressRoute.from(self.service, {
      '8080': 'cloud.danielramos.me',
    }),
  },
}
