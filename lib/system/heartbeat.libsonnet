local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    cron: k.batch.v1.cronJob.new('heartbeat', schedule='*/5 * * * *', containers=[
            container.new('ping', 'busybox:latest') +
            container.withCommand(['sh', '-c', 'wget -qO- "https://hc-ping.com/$UUID" >/dev/null 2>&1 || exit 1']) +
            container.withEnv(
              u.envVars.fromSecret(self.secretsEnv)
            ),
          ]) +
          k.batch.v1.cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
          k.batch.v1.cronJob.spec.withConcurrencyPolicy('Forbid'),

    secretsEnv: u.secret.forEnv(self.cron, {
      UUID: s.HEALTHCHECKS_UUID,
    }),
  },
}
