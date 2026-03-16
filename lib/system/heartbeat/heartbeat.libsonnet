local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'system/heartbeat/heartbeat.secrets.json';

{
  local container = k.core.v1.container,

  new():: {
    cron: k.batch.v1.cronJob.new('heartbeat', schedule='*/5 * * * *', containers=[
            container.new('ping', u.image(versions.heartbeat.image, versions.heartbeat.version)) +
            container.withCommand(['sh', '-c', 'wget -qO- "https://hc-ping.com/$UUID" >/dev/null 2>&1 || exit 1']) +
            container.withEnv(
              u.envVars.fromSealedSecret(self.sealed_secret)
            ),
          ]) +
          k.batch.v1.cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
          k.batch.v1.cronJob.spec.withConcurrencyPolicy('Forbid'),

    sealed_secret: u.sealedSecret.forEnv(self.cron, secrets.heartbeat),
  },
}
