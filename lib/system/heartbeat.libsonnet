local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

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

    sealed_secret: u.sealedSecret.forEnv(self.cron, {
      UUID: 'AgAaSUAgjIbdxX5JsMg1Gk+h8QToxmUacspFycJFf0t6IJmH1kAVbSojClIUbrYQUfRIeOglnMGHmiKc8gE+p93yThfk6pqLAwks+NR4zoJ0DVgYIlQ9h1d9OezL1I0A/0cP38h4oMi4/7IOaW2emRs2qShpwOf6QYhdLYjRmD9hpMFwaaTHON/7gH6fTFYpJsjJ/12uB8vSpmebIM9BxNPH/nsicJSq4ZHXJBO8Ka+IF5riqkUZPAG4FQsGwJsXJ7uMsNBCBxDmgJhD3Pq4muonEs+jXmT8NN3pmxJ4Fu+y3ShK5SGpK4qM0aL7hLLh67MsMAhWsK2fVxGbfFRjRE4587SFFld+l9a1iKubxufno5FlL7MNKhL/XA/TjAb9q9qKS/ZzMksET4/BTCL48jPeu3Iwl5iemB0FfFa3asbhubzR4ORkWpGa7iragzeuJJo5NHIObZUcEsDw7dhYVDSQ3yNgbBKPnQeH//jRYsNxKgtZPaO8YfH8uDlhJ9W8fMY0DhDQy925nW2kCzUvihDhx5QV8cf0cy/TS5nBGB/Rrht5zk47U3JK4UTbA+E6teStVRlvoECca2NO/X6uoiWxZShgi+4kYsTRAjXPcc7z52JO697/Vk9v9zHflUW1ImA3fymiODaQIf2sqNPQg7yQGtuy3nHC41ND5Dr8Ch9ltvQFOmNxEqJJxLQ1stYnroezAauktKIztgNzmA4ucXw6mvRy7M+b7HiYsZgY1aYvRrpGSTI=',
    }),
  },
}
