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
    deployment: deployment.new('jdownloader', replicas=1, containers=[
                  container.new('jdownloader', u.image(versions.jdownloader.image, versions.jdownloader.version)) +
                  container.withPorts([
                    containerPort.new('web', 5800),
                    containerPort.new('myjd', 3129),
                  ]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                    volumeMount.new('downloads', '/output'),
                  ]) +
                  u.probes.http('/', 5800),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromHostPath('config', '/data/jdownloader/config'),
                  u.volume.fromHostPath('downloads', '/cold-data/downloads'),
                ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      USER_ID: '1000',
      GROUP_ID: '100',
      KEEP_APP_RUNNING: '1',
      DISPLAY_WIDTH: '1920',
      DISPLAY_HEIGHT: '1080',
      TZ: 'Atlantic/Canary',
    }),
  },
}
