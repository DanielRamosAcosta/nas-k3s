local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'communications/mautrix-whatsapp/mautrix-whatsapp.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local configTemplate = importstr './mautrix-whatsapp.config.yaml';
// Shared appservice registration template (single source of truth, owned by Synapse).
local registrationTemplate = importstr 'communications/synapse/synapse.registration.yaml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  // AS/HS tokens are owned by Synapse (SealedSecret whatsapp-appservice-sealed-secret).
  // Reference that Secret by name so the appservice tokens match on both sides.
  local appserviceTokensRef = {
    metadata: { name: 'whatsapp-appservice-sealed-secret' },
    spec: { encryptedData: { AS_TOKEN: '', HS_TOKEN: '' } },
  },

  new():: {
    local this = self,

    deployment: deployment.new('mautrix-whatsapp', replicas=1, containers=[
                  container.new('mautrix-whatsapp', u.image(versions.mautrixWhatsapp.image, versions.mautrixWhatsapp.version)) +
                  // Bypass the image entrypoint (which rewrites /data/config.yaml via yq).
                  // -n/--no-update keeps the rendered config (and pickle_key) untouched.
                  container.withCommand(['/usr/bin/mautrix-whatsapp', '-c', '/data/config.yaml', '-r', '/data/registration.yaml', '-n']) +
                  container.withPorts([containerPort.new('appservice', 29318)]) +
                  container.withVolumeMounts([
                    volumeMount.new('data', '/data'),
                  ]) +
                  u.probes.tcp(29318),
                ]) +
                deployment.spec.template.spec.withInitContainers([
                  container.new('config-init', u.image(versions.envsubst.image, versions.envsubst.version)) +
                  container.withCommand(['/bin/sh', '-c', 'envsubst < /tpl/config.yaml > /data/config.yaml && envsubst < /tpl/registration.yaml > /data/registration.yaml']) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(this.sealedSecret) +
                    u.envVars.fromSealedSecret(this.sealedSecretDb) +
                    u.envVars.fromSealedSecret(appserviceTokensRef)
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('mautrix-whatsapp-config-tpl', '/tpl/config.yaml') + volumeMount.withSubPath('config.yaml'),
                    volumeMount.new('mautrix-whatsapp-registration-tpl', '/tpl/registration.yaml') + volumeMount.withSubPath('registration.yaml'),
                    volumeMount.new('data', '/data'),
                  ]),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  u.volume.fromConfigMap(this.configTemplate),
                  u.volume.fromConfigMap(this.registrationConfig),
                  { name: 'data', emptyDir: {} },
                ]) +
                deployment.spec.template.spec.withEnableServiceLinks(false),

    service: k.util.serviceFor(self.deployment),

    configTemplate: u.configMap.forFile('config.yaml', configTemplate) + { metadata+: { name: 'mautrix-whatsapp-config-tpl' } },
    registrationConfig: u.configMap.forFile('registration.yaml', registrationTemplate) + { metadata+: { name: 'mautrix-whatsapp-registration-tpl' } },

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.mautrixWhatsapp),
    sealedSecretDb: u.sealedSecret.wide.forEnvNamed('mautrix-whatsapp-db-sealed-secret', { DB_PASSWORD: postgresSecrets.userMautrixWhatsapp }),
  },
}
