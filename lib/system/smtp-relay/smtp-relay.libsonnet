local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'system/smtp-relay/smtp-relay.secrets.json';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('smtp-relay', replicas=1, containers=[
                  container.new('smtp-relay', u.image(versions.smtpRelay.image, versions.smtpRelay.version))
                  + container.withPorts([containerPort.new('smtp', 587)])
                  + container.withEnv(
                    u.envVars.fromSealedSecret(self.sealedSecret)
                    + u.envVars.fromConfigMap(self.config)
                  )
                  + container.withVolumeMounts([
                    volumeMount.new('spool', '/var/spool/postfix'),
                  ])
                  + u.probes.exec(['/scripts/healthcheck.sh']),
                ])
                + deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath('spool', '/data/smtp-relay')
                  + volume.hostPath.withType('DirectoryOrCreate'),
                ])
                + deployment.spec.strategy.withType('Recreate'),

    service: k.util.serviceFor(self.deployment),

    config: u.configMap.forEnv(self.deployment, {
      RELAYHOST: 'smtp.eu.mailgun.org:587',
      RELAYHOST_USERNAME: 'nas@mail.danielramos.me',
      ALLOWED_SENDER_DOMAINS: 'danielramos.me mail.danielramos.me',
      POSTFIX_myhostname: 'smtp-relay',
      POSTFIX_smtp_tls_security_level: 'encrypt',
      POSTFIX_message_size_limit: '26214400',
      LOG_FORMAT: 'json',
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.smtpRelay),
  },
}
