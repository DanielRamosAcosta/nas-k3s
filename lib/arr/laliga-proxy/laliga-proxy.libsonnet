local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('laliga-proxy', replicas=1, containers=[
                  container.new('laliga-proxy', u.image(versions.laligaProxy.image, versions.laligaProxy.version)) +
                  container.withPorts([
                    containerPort.new('http-proxy', 8888),
                    containerPort.new('health', 9090),
                  ]) +
                  container.withEnv(u.envVars.fromConfigMap(self.config)) +
                  container.resources.withRequests({ cpu: '10m', memory: '16Mi' }) +
                  container.resources.withLimits({ cpu: '200m', memory: '64Mi' }) +
                  u.probes.http('/healthz', 9090),
                ]) +
                deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forEnv(self.deployment, {
      // Point the *arr apps' HTTP proxy at laliga-proxy.arr.svc.cluster.local:8888
      LALIGA_PROXY_LISTEN: '0.0.0.0:8888',
      LALIGA_PROXY_HEALTH_LISTEN: '0.0.0.0:9090',
      // When LaLiga is blocking, chain through gluetun's HTTP proxy (VPN egress).
      LALIGA_PROXY_UPSTREAM: 'gluetun.system.svc.cluster.local:8888',
      LALIGA_PROXY_POLL_INTERVAL: '30',
      LALIGA_PROXY_BLOCK_THRESHOLD: '0.5',
      // Switch to the VPN fast, switch back to direct conservatively.
      LALIGA_PROXY_BLOCK_CONFIRM: '1',
      LALIGA_PROXY_UNBLOCK_CONFIRM: '3',
      LALIGA_PROXY_FAIL_MODE: 'keep',
      LALIGA_PROXY_LOG_FORMAT: 'json',
      LALIGA_PROXY_LOG_LEVEL: 'info',
    }),
  },
}
