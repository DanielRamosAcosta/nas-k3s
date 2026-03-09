local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='ghcr.io/qdm12/gluetun', version='v3.41.1'):: {
    deployment: deployment.new('gluetun', replicas=1, containers=[
      container.new('gluetun', u.image(image, version)) +
      container.securityContext.withPrivileged(true) +
      container.withPorts([
        containerPort.new('http-proxy', 8888),
      ]) +
      container.withEnv(
        u.envVars.fromSecret(self.secrets) +
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

    secrets: u.secret.forEnv(self.deployment, {
      OPENVPN_USER: s.PROTONVPN_OPENVPN_USER,
      OPENVPN_PASSWORD: s.PROTONVPN_OPENVPN_PASSWORD,
    }),
  },
}
