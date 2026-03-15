local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/invidious.secrets.json';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

{
  local deployment = k.apps.v1.deployment,
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local this = self,

    deployment: deployment.new('invidious', replicas=1, containers=[
                  container.new('invidious', u.image(versions.invidious.image, versions.invidious.version)) +
                  container.withPorts([containerPort.new('http', 3000)]) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealed_secret)
                  ),
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment),

    sealed_secret: u.sealedSecret.wide.forEnv(self.deployment, secrets.invidious),

    ingressRoute: u.ingressRoute.from(self.service, 'invidious.danielramos.me'),

    companionDeployment: deployment.new('invidious-companion', replicas=1, containers=[
                           container.new('invidious-companion', u.image(versions.invidiousCompanion.image, versions.invidiousCompanion.version)) +
                           container.withPorts([containerPort.new('http', 8282)]) +
                           container.withEnv(
                             u.envVars.fromSealedSecret(self.companion_sealed_secret)
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

    companion_sealed_secret: u.sealedSecret.forEnv(self.companionDeployment, secrets.companion),
  },
}
