local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

local invidiousConfig = import './invidious.config.json';

{
  local deployment = k.apps.v1.deployment,
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new(
    invidiousImage='quay.io/invidious/invidious',
    invidiousCompanionImage='quay.io/invidious/invidious-companion',
    invidiousVersion,
    invidiousCompanionVersion
  ):: {
    local this = self,

    deployment: deployment.new('invidious', replicas=1, containers=[
                  container.new('invidious', u.image(invidiousImage, invidiousVersion)) +
                  container.withImagePullPolicy('Always') +
                  container.withPorts([containerPort.new('http', 3000)]) +
                  container.withEnv(
                    u.envVars.fromSecret(self.secretEnv)
                  ),
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment),

    secretEnv: u.secret.forEnv(self.deployment, {
      INVIDIOUS_CONFIG: std.manifestYamlDoc(invidiousConfig {
        db+: {
          password: s.POSTGRES_PASSWORD_INVIDIOUS,
        },
        invidious_companion_key: s.INVIDIOUS_COMPANION_KEY,
        hmac_key: s.INVIDIOUS_HMAC_KEY,
      }),
    }),

    ingressRoute: u.ingressRoute.from(self.service, 'invidious.danielramos.me'),

    companionDeployment: deployment.new('invidious-companion', replicas=1, containers=[
                           container.new('invidious-companion', u.image(invidiousCompanionImage, invidiousCompanionVersion)) +
                           container.withImagePullPolicy('Always') +
                           container.withPorts([containerPort.new('http', 8282)]) +
                           container.withEnv(
                             u.envVars.fromSecret(self.companionSecretEnv)
                           ) +
                           container.withVolumeMounts([
                             volumeMount.new('cache', '/var/tmp/youtubei.js'),
                           ]),
                         ]) +
                         deployment.spec.template.spec.withVolumes([
                           volume.fromHostPath('cache', '/data/invidious/companion-cache') + volume.hostPath.withType('DirectoryOrCreate'),
                         ]) +
                         deployment.spec.template.spec.withEnableServiceLinks(false),

    companionService: k.util.serviceFor(self.companionDeployment),

    companionSecretEnv: u.secret.forEnv(self.companionDeployment, {
      SERVER_SECRET_KEY: s.INVIDIOUS_COMPANION_KEY,
    }),
  },
}
