local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'communications/synapse/synapse.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local homeserverTemplate = importstr './synapse.homeserver.yaml';
local logConfigContent = importstr './synapse.log.yaml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local this = self,

    deployment: deployment.new('synapse', replicas=1, containers=[
                  container.new('synapse', u.image(versions.synapse.image, versions.synapse.version)) +
                  container.withEnv([{ name: 'SYNAPSE_CONFIG_PATH', value: '/config/homeserver.yaml' }]) +
                  container.withPorts([
                    containerPort.new('http', 8008),
                    containerPort.new('metrics', 9090),
                  ]) +
                  container.withVolumeMounts([
                    volumeMount.new('config', '/config'),
                    volumeMount.new('synapse-log-config', '/log-config/log.yaml') + volumeMount.withSubPath('log.yaml'),
                    u.volumeMount.fromSealedSecretFile(this.signingKey, '/keys'),
                    volumeMount.new('media', '/media'),
                    volumeMount.new('data', '/data'),
                  ]) +
                  u.probes.withStartup.http('/_matrix/client/versions', 8008),
                ]) +
                deployment.spec.template.spec.withInitContainers([
                  container.new('config-init', u.image(versions.envsubst.image, versions.envsubst.version)) +
                  container.withCommand(['/bin/sh', '-c', 'envsubst < /tpl/homeserver.yaml > /config/homeserver.yaml']) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(this.sealedSecret) +
                    u.envVars.fromSealedSecret(this.sealedSecretDb)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('synapse-homeserver-tpl', '/tpl/homeserver.yaml') + volumeMount.withSubPath('homeserver.yaml'),
                    volumeMount.new('config', '/config'),
                  ]),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromConfigMap(this.homeserverConfig),
                  u.volume.fromConfigMap(this.logConfig),
                  { name: 'config', emptyDir: {} },
                  u.volume.fromSealedSecret(this.signingKey),
                  volume.fromHostPath('media', '/cold-data/synapse/media'),
                  { name: 'data', emptyDir: {} },
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment) + u.metrics(port='9090', path='/metrics'),

    ingressRoute: u.ingressRoute.from(self.service, 'matrix.danielramos.me'),

    homeserverConfig: u.configMap.forFile('homeserver.yaml', homeserverTemplate) + { metadata+: { name: 'synapse-homeserver-tpl' } },
    logConfig: u.configMap.forFile('log.yaml', logConfigContent) + { metadata+: { name: 'synapse-log-config' } },

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.synapse),
    sealedSecretDb: u.sealedSecret.wide.forEnvNamed('synapse-db-sealed-secret', { SYNAPSE_DB_PASSWORD: postgresSecrets.userSynapse }),
    signingKey: u.sealedSecret.forFile('signing.key', secrets.signingKey),
  },
}
