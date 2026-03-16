local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('jellyfin', replicas=1, containers=[
                   container.new('jellyfin', u.image(versions.jellyfin.image, versions.jellyfin.version)) +
                   container.withPorts([containerPort.new('http', 8096)]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('config', '/config'),
                     volumeMount.new('cache', '/cache'),
                     volumeMount.new('media', '/media', true),
                     volumeMount.new('dri', '/dev/dri/renderD128') + volumeMount.withSubPath('renderD128'),
                   ]),
                 ]) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromPersistentVolumeClaim('config', self.configPvc.metadata.name),
                   volume.fromPersistentVolumeClaim('cache', self.cachePvc.metadata.name),
                   volume.fromHostPath('media', '/cold-data/media') + volume.hostPath.withType('DirectoryOrCreate'),
                   volume.fromHostPath('dri', '/dev/dri') + volume.hostPath.withType('Directory'),
                 ]) +
                 statefulSet.spec.template.spec.securityContext.withSupplementalGroups([303, 26]) +
                 statefulSet.spec.template.spec.securityContext.withFsGroup(1000),

    service: k.util.serviceFor(self.statefulSet),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      JELLYFIN_PublishedServerUrl: 'https://media.danielramos.me',
    }),

    configPv: u.pv.atLocal('jellyfin-config-pv', '25Gi', '/data/jellyfin/config'),
    configPvc: u.pvc.from(self.configPv),

    cachePv: u.pv.atLocal('jellyfin-cache-pv', '25Gi', '/data/jellyfin/cache'),
    cachePvc: u.pvc.from(self.cachePv),

    ingressRoute: u.ingressRoute.from(self.service, 'media.danielramos.me'),
  },
}
