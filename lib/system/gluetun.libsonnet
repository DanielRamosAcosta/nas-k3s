local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'system/gluetun.secrets.json';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('gluetun', replicas=1, containers=[
      container.new('gluetun', u.image(versions.gluetun.image, versions.gluetun.version)) +
      container.securityContext.withPrivileged(true) +
      container.withPorts([
        containerPort.new('http-proxy', 8888),
      ]) +
      container.withEnv(
        u.envVars.fromSealedSecret(self.sealed_secret) +
        u.envVars.fromConfigMap(self.config)
      ),
    ]) +
    deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forEnv(self.deployment, {
      VPN_SERVICE_PROVIDER: 'protonvpn',
      VPN_TYPE: 'openvpn',
      FREE_ONLY: 'on',
      HTTPPROXY: 'on',
    }),

    sealed_secret: u.sealedSecret.forEnv(self.deployment, secrets.gluetun),
  },
}
