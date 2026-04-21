local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('jellyfin', replicas=1, containers=[
                  container.new('jellyfin', u.image(versions.jellyfin.image, versions.jellyfin.version)) +
                  container.withPorts([containerPort.new('http', 8096)]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                    volumeMount.new('cache', '/cache'),
                    volumeMount.new('media', '/media', true),
                    volumeMount.new('dri', '/dev/dri'),
                  ]) +
                  u.probes.withStartup.http('/health', 8096),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath('config', '/data/jellyfin/config'),
                  volume.fromHostPath('cache', '/data/jellyfin/cache'),
                  volume.fromHostPath('media', '/cold-data/media') + volume.hostPath.withType('DirectoryOrCreate'),
                  volume.fromHostPath('dri', '/dev/dri') + volume.hostPath.withType('Directory'),
                ]) +
                deployment.spec.template.spec.securityContext.withSupplementalGroups([303, 26]) +
                deployment.spec.template.spec.securityContext.withFsGroup(1000),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      JELLYFIN_PublishedServerUrl: 'https://media.danielramos.me',
    }),

    ingressRoute: u.ingressRoute.from(self.service, 'media.danielramos.me'),
  },
}
