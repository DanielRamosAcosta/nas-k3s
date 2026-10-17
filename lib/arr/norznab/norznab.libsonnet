local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'arr/norznab/norznab.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('norznab', replicas=1, containers=[
                  container.new('norznab', u.image(versions.norznab.image, versions.norznab.version)) +
                  container.withPorts([
                    containerPort.new('http', 3000),
                  ]) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealedSecret) +
                    u.envVars.fromConfigMap(self.config)
                  ) +
                  u.probes.tcp(3000),
                ]) +
                deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forEnv(self.deployment, {
      // DonTorrent sale por Tor (exit node de clearnet, NO el .onion — su hidden
      // service dejó de resolver: "No more HSDir available to query"). El clearnet
      // está bloqueado por SNI-DPI del ISP (RST en el ClientHello), pero el circuito
      // Tor evita el DPI. norznab aprende el dominio en caliente siguiendo los 301
      // (dontorrent rota de dominio periódicamente).
      DON_TORRENT_BASE_URL: 'https://dontorrent.channel',
      DON_TORRENT_USE_TOR: 'true',
      DON_TORRENT_TOR_PROXY: 'http://tor-proxy.arr.svc.cluster.local:8118',
      DON_TORRENT_USE_ONION: 'false',
      MARCIANO_TORRENT_BASE_URL: 'https://marcianotorrent.net',
      REQUEST_TIMEOUT_MS: '120000',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.norznab),
  },
}
