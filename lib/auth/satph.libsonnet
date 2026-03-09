local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

local autheliaConfig = importstr './authelia.config.yml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='ghcr.io/danielramosacosta/satph', version):: {
    deployment: deployment.new('satph', replicas=1, containers=[
      container.new('satph', u.image(image, version)) +
      container.withPorts([containerPort.new('http', 3000)]) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv)
      ),
    ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      // AUTHELIA_BASE_URL: 'http://authelia.auth.svc.cluster.local:9091',
      AUTHELIA_BASE_URL: 'https://auth.danielramos.me',
    }),
  },
}
