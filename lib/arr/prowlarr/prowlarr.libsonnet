local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local torrentioDefinition = importstr 'arr/prowlarr/definitions/torrentio.yml';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('prowlarr', replicas=1, containers=[
                  container.new('prowlarr', u.image(versions.prowlarr.image, versions.prowlarr.version)) +
                  container.withPorts([
                    containerPort.new('http', 9696),
                  ]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                  ]) +
                  u.probes.http('/ping', 9696),
                ]) +
                // Cardigann custom definitions (p. ej. Torrentio) se copian al hostPath
                // en vez de montarse read-only dentro de /config: el entrypoint de hotio
                // corre como root y hace chown -R /config, que fallaría sobre un montaje RO.
                deployment.spec.template.spec.withInitContainers(
                  container.new('install-definitions', u.image(versions.busybox.image, versions.busybox.version)) +
                  container.withCommand(['sh', '-c', 'mkdir -p /config/Definitions/Custom && cp /src/torrentio.yml /config/Definitions/Custom/torrentio.yml']) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                    u.volumeMount.fromFile(self.torrentioDefinition, '/src'),
                  ])
                ) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromHostPath('config', '/data/arr/prowlarr'),
                  u.volume.fromConfigMap(self.torrentioDefinition),
                ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      PUID: '1000',
      PGID: '100',
      UMASK: '002',
      TZ: 'Atlantic/Canary',
      PROWLARR__LOG__CONSOLEFORMAT: 'Clef',
    }),

    torrentioDefinition: u.configMap.forFile('torrentio.yml', torrentioDefinition),
  },
}
