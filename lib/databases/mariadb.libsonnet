local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';
local versions = import 'versions.json';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  local dataVolumeName = 'data',

  local createUserMigration = importstr './mariadb.create-user.sh',

  new():: {
    statefulSet: statefulSet.new('mariadb', replicas=1, containers=[
      container.new('mariadb', u.image(versions.mariadb.image, versions.mariadb.version)) +
      container.withPorts(
        [containerPort.new('mariadb', 3306)]
      ) +
      container.withEnv(
        u.envVars.fromSecret(self.secretsEnv)
      ) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/config'),
      ]),
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromPersistentVolumeClaim(dataVolumeName, self.pvc.metadata.name),
    ]),

    service: k.util.serviceFor(self.statefulSet),

    secretsEnv: u.secret.forEnv(self.statefulSet, {
      MYSQL_ROOT_PASSWORD: s.MARIADB_ROOT_PASSWORD,
      PUID: '1000',
      PGID: '1000',
      TZ: 'Atlantic/Canary',
    }),

    userBooklore: self.createUser('booklore', s.MARIADB_PASSWORD_BOOKLORE, self.createUserMigration, self.secretsEnv),

    createUserMigration: u.configMap.forFile('mariadb.create-user.sh', createUserMigration),

    pv: u.pv.localPathFor(self.statefulSet, '10Gi', '/data/mariadb/data'),
    pvc: u.pvc.from(self.pv),

    createUser(name, password, configMap, secret):: {
      migrationJob: k.batch.v1.job.new('mariadb-create-user-' + name) +
                    k.batch.v1.job.spec.template.spec.withRestartPolicy('OnFailure') +
                    k.batch.v1.job.spec.template.spec.withContainers([
                      container.new('create-user', u.image(versions.mariadb.image, versions.mariadb.version)) +
                      container.withCommand(['/bin/bash', '/mnt/scripts/mariadb.create-user.sh']) +
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
