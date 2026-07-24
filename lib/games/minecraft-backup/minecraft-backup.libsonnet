local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'games/minecraft-backup/minecraft-backup.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local cronJob = k.batch.v1.cronJob,
  local container = k.core.v1.container,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local envVar = k.core.v1.envVar,

  new():: {
    cronJob: cronJob.new(name='minecraft-backup', schedule='0 5 * * *', containers=[
               container.new('backup', u.image(versions.mcBackup.image, versions.mcBackup.version)) +
               container.withEnv(
                 u.envVars.fromConfigMap(self.configEnv) +
                 u.envVars.fromSealedSecret(self.sealedSecret) +
                 [envVar.fromSecretRef('RCON_PASSWORD', 'minecraft-rcon', 'RCON_PASSWORD')]
               ) +
               container.withVolumeMounts([
                 volumeMount.new('data', '/data', true),
                 volumeMount.new('backups', '/backups'),
               ]),
             ]) +
             cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
             cronJob.spec.withConcurrencyPolicy('Forbid') +
             cronJob.spec.withSuccessfulJobsHistoryLimit(3) +
             cronJob.spec.withFailedJobsHistoryLimit(3) +
             cronJob.spec.jobTemplate.spec.template.spec.securityContext.withRunAsUser(1000) +
             cronJob.spec.jobTemplate.spec.template.spec.securityContext.withRunAsGroup(1000) +
             cronJob.spec.jobTemplate.spec.template.spec.withVolumes([
               volume.fromHostPath('data', '/data/minecraft'),
               volume.fromHostPath('backups', '/cold-data/minecraft'),
             ]),

    sealedSecret: u.sealedSecret.forEnvNamed('minecraft-restic', secrets.minecraftRestic),

    configEnv: u.configMap.forEnv(self.cronJob, {
      BACKUP_METHOD: 'restic',
      SRC_DIR: '/data',
      RESTIC_REPOSITORY: '/backups',
      BACKUP_INTERVAL: '0',
      PRUNE_RESTIC_RETENTION: '--keep-daily 7 --keep-weekly 4 --keep-monthly 6',
      RCON_HOST: 'minecraft',
      RCON_PORT: '25575',
      BACKUP_NAME: 'minecraft',
    }),
  },
}
