local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

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
        u.envVars.fromSecret(self.secretsEnv)
      ) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/var/lib/postgresql/data'),
        volumeMount.new('backup-storage', '/backups'),
      ]),
    ]) + statefulSet.spec.template.spec.withInitContainers([
      container.new('setup-postgres-config', 'busybox:latest') +
      container.withCommand(['/bin/sh', '-c', 'cat /config/postgresql.auto.conf > /var/lib/postgresql/data/postgresql.auto.conf && cat /pg_hba/pg_hba.conf > /var/lib/postgresql/data/pg_hba.conf']) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/var/lib/postgresql/data'),
        volumeMount.new('backup-config-vol', '/config'),
        volumeMount.new('pg-hba-vol', '/pg_hba'),
      ]) +
      { securityContext: { runAsUser: 999, runAsGroup: 999 } },
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromPersistentVolumeClaim(dataVolumeName, self.pvc.metadata.name),
      volume.fromPersistentVolumeClaim('backup-storage', self.backupPvc.metadata.name),
      { name: 'backup-config-vol', configMap: { name: 'postgresql-auto-conf' } },
      { name: 'pg-hba-vol', configMap: { name: 'pg-hba-conf' } },
    ]),

    service: k.util.serviceFor(self.statefulSet),

    secretsEnv: u.secret.forEnv(self.statefulSet, {
      POSTGRES_PASSWORD: s.POSTGRES_PASSWORD,
    }),

    userImmich: self.createUser('immich', s.POSTGRES_PASSWORD_IMMICH, self.createUserMigration, self.secretsEnv),
    userAuthelia: self.createUser('authelia', s.POSTGRES_PASSWORD_AUTHELIA, self.createUserMigration, self.secretsEnv),
    userSftpgo: self.createUser('sftpgo', s.POSTGRES_PASSWORD_SFTPGO, self.createUserMigration, self.secretsEnv),
    userGrafana: self.createUser('grafana', s.POSTGRES_PASSWORD_GRAFANA, self.createUserMigration, self.secretsEnv),
    userGitea: self.createUser('gitea', s.POSTGRES_PASSWORD_GITEA, self.createUserMigration, self.secretsEnv),
    userPiped: self.createUser('piped', s.POSTGRES_PASSWORD_PIPED, self.createUserMigration, self.secretsEnv),
    userInvidious: self.createUser('invidious', s.POSTGRES_PASSWORD_INVIDIOUS, self.createUserMigration, self.secretsEnv),

    createUserMigration: u.configMap.forFile('postgres.create-user.sh', createUserMigration),

    // Backup scripts ConfigMaps
    backupScriptConfigMap: u.configMap.forFile('postgres.backup.sh', backupScript),
    cleanupScriptConfigMap: u.configMap.forFile('postgres.cleanup.sh', cleanupScript),

    pv: u.pv.localPathFor(self.statefulSet, '40Gi', '/data/postgres/data'),
    pvc: u.pvc.from(self.pv),

    // PostgreSQL configuration
    backupConfig: u.configMap.forFile('postgresql.auto.conf', backupConfigContent),
    pgHbaConfig: u.configMap.forFile('pg_hba.conf', pgHbaContent),

    // Backup storage
    backupPv: u.pv.atLocal('postgres-backup-pv', '100Gi', '/cold-data/postgres-backups'),
    backupPvc: u.pvc.from(self.backupPv),

    // Secrets for backup CronJobs (different name to avoid conflicts with secretsEnv)
    backupSecrets: k.core.v1.secret.new('postgres-backup-secret-env', u.base64Keys({
      PGPASSWORD: s.POSTGRES_PASSWORD,
    })),

    // Base Backup CronJob - runs daily at 2 AM
    baseBackupCron: cronJob.new(
                      name='postgres-base-backup',
                      schedule='0 2 * * *',
                      containers=[
                        container.new('backup', u.image(versions.postgres.image, versions.postgres.version)) +
                        container.withCommand(['/bin/bash', '/mnt/scripts/postgres.backup.sh']) +
                        container.withEnv(
                          u.envVars.fromSecret(self.backupSecrets)
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
                      volume.fromPersistentVolumeClaim('backup-storage', self.backupPvc.metadata.name),
                      u.volume.fromConfigMap(self.backupScriptConfigMap),
                    ]),

    // Cleanup CronJob - runs daily at 3 AM (after backup)
    cleanupCron: cronJob.new(
                   name='postgres-backup-cleanup',
                   schedule='0 3 * * *',
                   containers=[
                     container.new('cleanup', 'busybox:latest') +
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
                   volume.fromPersistentVolumeClaim('backup-storage', self.backupPvc.metadata.name),
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
                        u.envVars.fromSecret(self.userSecret) +
                        u.envVars.fromSecret(secret)
                      ) +
                      container.withVolumeMounts([
                        u.volumeMount.fromFile(configMap, '/mnt/scripts'),
                      ]),
                    ]) +
                    k.batch.v1.job.spec.template.spec.withVolumes([
                      u.volume.fromConfigMap(configMap),
                    ]),

      userSecret: u.secret.forEnv(self.migrationJob, {
        USER_PASSWORD: password,
      }),
    },
  },
}
