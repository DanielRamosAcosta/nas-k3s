local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'communications/synapse/synapse.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local homeserverConfig = importstr './synapse.homeserver.yaml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local envVar = k.core.v1.envVar,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local this = self,

    deployment: deployment.new('synapse', replicas=1, containers=[
                  container.new('synapse', u.image(versions.synapse.image, versions.synapse.version)) +
                  container.withEnv([
                    { name: 'SYNAPSE_CONFIG_PATH', value: '/config/homeserver.yaml' },
                    envVar.fromSecretRef('PGPASSWORD', this.sealedSecretDb.metadata.name, 'SYNAPSE_DB_PASSWORD'),
                  ]) +
                  container.withPorts([
                    containerPort.new('http', 8008),
                    containerPort.new('metrics', 9090),
                  ]) +
                  container.withVolumeMounts([
                    volumeMount.new('synapse-config', '/config'),
                    volumeMount.new(this.secretFiles.metadata.name, '/secrets'),
                    u.volumeMount.fromSealedSecretFile(this.signingKey, '/keys'),
                    u.volumeMount.fromSealedSecretFile(this.registrationFile, '/appservice'),
                    volumeMount.new('media', '/media'),
                    volumeMount.new('data', '/data'),
                  ]) +
                  u.probes.withStartup.http('/_matrix/client/versions', 8008),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromConfigMap(this.homeserverConfig),
                  u.volume.fromSealedSecret(this.secretFiles),
                  u.volume.fromSealedSecret(this.signingKey),
                  u.volume.fromSealedSecret(this.registrationFile),
                  volume.fromHostPath('media', '/cold-data/synapse/media'),
                  { name: 'data', emptyDir: {} },
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment) + u.metrics(port='9090', path='/metrics'),

    ingressRoute: u.ingressRoute.from(self.service, 'matrix.danielramos.me'),

    homeserverConfig: u.configMap.forFile('homeserver.yaml', homeserverConfig) + { metadata+: { name: 'synapse-config' } },

    secretFiles: u.sealedSecret.forEnvNamed('synapse-secrets', secrets.synapseSecrets),
    registrationFile: u.sealedSecret.forFile('registration.yaml', secrets.registrationFile),
    signingKey: u.sealedSecret.forFile('signing.key', secrets.signingKey),
    sealedSecretDb: u.sealedSecret.wide.forEnvNamed('synapse-db-sealed-secret', { SYNAPSE_DB_PASSWORD: postgresSecrets.userSynapse }),
    appserviceSecret: u.sealedSecret.forEnvNamed('whatsapp-appservice-sealed-secret', secrets.whatsappAppservice),
  },
}
