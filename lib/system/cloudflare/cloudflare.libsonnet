local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'system/cloudflare/cloudflare.secrets.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('cloudflare-ddns', replicas=1, containers=[
      container.new('cloudflare-ddns', u.image(versions.cloudflare.image, versions.cloudflare.version)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) +
        u.envVars.fromSealedSecret(self.sealed_secret),
      ),
    ]),

    configEnv: u.configMap.forEnv(self.deployment, {
      DOMAINS: 'nas.danielramos.me',
      PROXIED: 'true',
    }),

    sealed_secret: u.sealedSecret.forEnv(self.deployment, secrets.cloudflare),
  },
}
