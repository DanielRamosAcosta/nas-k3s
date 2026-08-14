local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('tor-proxy', replicas=1, containers=[
                  container.new('tor-proxy', u.image(versions.torProxy.image, versions.torProxy.version)) +
                  container.withPorts([
                    containerPort.new('http-tunnel', 8118),
                  ]) +
                  container.withVolumeMounts([
                    volumeMount.new('torrc', '/etc/tor/torrc') +
                    volumeMount.withSubPath('torrc'),
                  ]) +
                  container.resources.withRequests({ cpu: '50m', memory: '64Mi' }) +
                  container.resources.withLimits({ cpu: '200m', memory: '128Mi' }) +
                  u.probes.tcp(8118),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromConfigMap(self.config),
                ]) +
                deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forFile('torrc', |||
      # Tor configuration for norznab .onion access
      # HTTPTunnelPort enables HTTP CONNECT proxy (undici ProxyAgent compatible)
      HTTPTunnelPort 0.0.0.0:8118
      # Keep SOCKS port disabled to reduce attack surface
      SocksPort 0
    |||),
  },
}
