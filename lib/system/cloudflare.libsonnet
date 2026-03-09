local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='docker.io/favonia/cloudflare-ddns', version):: {
    deployment: deployment.new('cloudflare-ddns', replicas=1, containers=[
      container.new('cloudflare-ddns', u.image(image, version)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSecret(self.secretsEnv),
      ),
    ]),

    configEnv: u.configMap.forEnv(self.deployment, {
      DOMAINS: 'nas.danielramos.me',
      PROXIED: 'true',
    }),

    secretsEnv: u.secret.forEnv(self.deployment, {
      CLOUDFLARE_API_TOKEN: s.CLOUDFLARE_API_TOKEN,
    }),
  },
}
