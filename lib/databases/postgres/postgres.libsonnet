local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local secret = k.core.v1.secret,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,
  local configMap = k.core.v1.configMap,
  local cronJob = k.batch.v1.cronJob,

  local dataVolumeName = 'data',

  local createUserMigration = importstr './postgres.create-user.sh',
  local backupConfigContent = importstr './postgres.config.conf',
  local backupScript = importstr './postgres.backup.sh',
  local cleanupScript = importstr './postgres.cleanup.sh',
  local pgHbaContent = importstr './postgres.hba.conf',

  new():: {
    statefulSet: statefulSet.new('postgres', replicas=1, containers=[
      container.new('postgres', u.image(versions.postgres.image, versions.postgres.version)) +
      container.withPorts(
        [containerPort.new('postgres', 5432)]
      ) +
      container.withEnv(
        u.envVars.fromSealedSecret(self.sealedSecret)
      ) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/var/lib/postgresql/data'),
        volumeMount.new('backup-storage', '/backups'),
      ]) +
      u.probes.stateful.tcp(5432),
    ]) + statefulSet.spec.template.spec.withInitContainers([
      container.new('setup-postgres-config', u.image(versions.busybox.image, versions.busybox.version)) +
      container.withCommand(['/bin/sh', '-c', 'cat /config/postgresql.auto.conf > /var/lib/postgresql/data/postgresql.auto.conf && cat /pg_hba/pg_hba.conf > /var/lib/postgresql/data/pg_hba.conf']) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/var/lib/postgresql/data'),
        volumeMount.new('backup-config-vol', '/config'),
        volumeMount.new('pg-hba-vol', '/pg_hba'),
      ]) +
      { securityContext: { runAsUser: 999, runAsGroup: 999 } },
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromHostPath(dataVolumeName, '/data/postgres/data'),
      volume.fromHostPath('backup-storage', '/cold-data/postgres-backups'),
      { name: 'backup-config-vol', configMap: { name: 'postgresql-auto-conf' } },
      { name: 'pg-hba-vol', configMap: { name: 'pg-hba-conf' } },
    ]),

    service: k.util.serviceFor(self.statefulSet),

    sealedSecret: u.sealedSecret.wide.forEnv(self.statefulSet, secrets.postgres),

    userImmich: self.createUser('immich', secrets.userImmich, self.createUserMigration, self.sealedSecret),
    userAuthelia: self.createUser('authelia', secrets.userAuthelia, self.createUserMigration, self.sealedSecret),
    userSftpgo: self.createUser('sftpgo', secrets.userSftpgo, self.createUserMigration, self.sealedSecret),
    userGrafana: self.createUser('grafana', secrets.userGrafana, self.createUserMigration, self.sealedSecret),
    userInvidious: self.createUser('invidious', secrets.userInvidious, self.createUserMigration, self.sealedSecret),

    createUserMigration: u.configMap.forFile('postgres.create-user.sh', createUserMigration),

    // Backup scripts ConfigMaps
    backupScriptConfigMap: u.configMap.forFile('postgres.backup.sh', backupScript),
    cleanupScriptConfigMap: u.configMap.forFile('postgres.cleanup.sh', cleanupScript),

    // PostgreSQL configuration
    backupConfig: u.configMap.forFile('postgresql.auto.conf', backupConfigContent),
    pgHbaConfig: u.configMap.forFile('pg_hba.conf', pgHbaContent),

    // Sealed secret for backup CronJobs
    backupSecrets: u.sealedSecret.wide.forEnvNamed('postgres-backup-sealed-secret', {
      PGPASSWORD: secrets.postgres.POSTGRES_PASSWORD,
    }),

    // Base Backup CronJob - runs daily at 2 AM
    baseBackupCron: cronJob.new(
                      name='postgres-base-backup',
                      schedule='0 2 * * *',
                      containers=[
                        container.new('backup', u.image(versions.postgres.image, versions.postgres.version)) +
                        container.withCommand(['/bin/bash', '/mnt/scripts/postgres.backup.sh']) +
                        container.withEnv(
                          u.envVars.fromSealedSecret(self.backupSecrets)
                        ) +
                        container.withVolumeMounts([
                          volumeMount.new('backup-storage', '/backups'),
                          u.volumeMount.fromFile(self.backupScriptConfigMap, '/mnt/scripts'),
                        ]),
                      ]
                    ) +
                    cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
                    cronJob.spec.withConcurrencyPolicy('Forbid') +
                    cronJob.spec.withSuccessfulJobsHistoryLimit(3) +
                    cronJob.spec.withFailedJobsHistoryLimit(3) +
                    cronJob.spec.jobTemplate.spec.template.spec.withVolumes([
                      volume.fromHostPath('backup-storage', '/cold-data/postgres-backups'),
                      u.volume.fromConfigMap(self.backupScriptConfigMap),
                    ]),

    // Cleanup CronJob - runs daily at 3 AM (after backup)
    cleanupCron: cronJob.new(
                   name='postgres-backup-cleanup',
                   schedule='0 3 * * *',
                   containers=[
                     container.new('cleanup', u.image(versions.busybox.image, versions.busybox.version)) +
                     container.withCommand(['sh', '/mnt/scripts/postgres.cleanup.sh']) +
                     container.withVolumeMounts([
                       volumeMount.new('backup-storage', '/backups'),
                       u.volumeMount.fromFile(self.cleanupScriptConfigMap, '/mnt/scripts'),
                     ]),
                   ]
                 ) +
                 cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
                 cronJob.spec.withConcurrencyPolicy('Forbid') +
                 cronJob.spec.jobTemplate.spec.template.spec.withVolumes([
                   volume.fromHostPath('backup-storage', '/cold-data/postgres-backups'),
                   u.volume.fromConfigMap(self.cleanupScriptConfigMap),
                 ]),

    createUser(name, password, configMap, secret):: {
      migrationJob: k.batch.v1.job.new('postgres-create-user-' + name) +
                    k.batch.v1.job.spec.template.spec.withRestartPolicy('OnFailure') +
                    k.batch.v1.job.spec.template.spec.withContainers([
                      container.new('create-user', u.image(versions.postgres.image, versions.postgres.version)) +
                      container.withCommand(['/bin/bash', '/mnt/scripts/postgres.create-user.sh']) +
                      container.withEnv(
                        [k.core.v1.envVar.new('USER_NAME', name)] +
                        u.envVars.fromSealedSecret(self.userSecret) +
                        u.envVars.fromSealedSecret(secret)
                      ) +
                      container.withVolumeMounts([
                        u.volumeMount.fromFile(configMap, '/mnt/scripts'),
                      ]),
                    ]) +
                    k.batch.v1.job.spec.template.spec.withVolumes([
                      u.volume.fromConfigMap(configMap),
                    ]),

      userSecret: u.sealedSecret.wide.forEnv(self.migrationJob, {
        USER_PASSWORD: password,
      }),
    },
  },
}
