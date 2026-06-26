local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'databases/couchdb/couchdb.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  local dataVolumeName = 'data',

  local createUserMigration = importstr './couchdb.create-user.sh',

  new():: {
    local this = self,

    statefulSet: statefulSet.new('couchdb', replicas=1, containers=[
      container.new('couchdb', u.image(versions.couchdb.image, versions.couchdb.version)) +
      container.withPorts(
        [containerPort.new('couchdb', 5984)]
      ) +
      container.withEnv(
        // COUCHDB_USER/COUCHDB_PASSWORD bootstrapean el admin; COUCHDB_SECRET firma
        // las cookies de sesión para que persistan entre reinicios (el local.ini
        // runtime no se persiste en el hostPath).
        u.envVars.fromSealedSecret(self.sealedSecret)
      ) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/opt/couchdb/data'),
        // Monta el .ini como archivo (subPath) en local.d/ — coexiste con el
        // docker.ini que genera la imagen, sin shadowear el directorio.
        u.volumeMount.fromFile(self.config, '/opt/couchdb/etc/local.d'),
      ]) +
      // require_valid_user=true → un GET a /_up da 401, así que probe TCP, no HTTP.
      u.probes.stateful.tcp(5984),
    ]) +
    // Correr como uid 5984 (couchdb): el entrypoint de la imagen, si arranca como
    // root, hace chown -R sobre /opt/couchdb e intenta chownear nuestro config.ini
    // (montaje de ConfigMap read-only) → falla con set -e y aborta sin loguear.
    statefulSet.spec.template.spec.securityContext.withRunAsUser(5984) +
    statefulSet.spec.template.spec.securityContext.withRunAsGroup(5984) +
    statefulSet.spec.template.spec.securityContext.withFsGroup(5984) +
    statefulSet.spec.template.spec.withInitContainers([
      // La imagen oficial corre como uid 5984; el hostPath se crea como root.
      // Este init corre como root (override del securityContext de pod) para chownear.
      container.new('fix-perms', u.image(versions.busybox.image, versions.busybox.version)) +
      container.withCommand(['/bin/sh', '-c', 'chown -R 5984:5984 /opt/couchdb/data']) +
      container.withVolumeMounts([
        volumeMount.new(dataVolumeName, '/opt/couchdb/data'),
      ]) +
      { securityContext: { runAsUser: 0 } },
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromHostPath(dataVolumeName, '/data/couchdb'),
      u.volume.fromConfigMap(self.config),
    ]),

    service: k.util.serviceFor(self.statefulSet),

    config: u.configMap.forFile('couchdb.config.ini', importstr './couchdb.config.ini'),

    // Strict scope (namespace databases): el único consumidor en el clúster es el
    // Job de migración; la password de 'obsidian' se introduce a mano en el plugin.
    sealedSecret: u.sealedSecret.forEnv(self.statefulSet, secrets.couchdb),

    createUserMigration: u.configMap.forFile('couchdb.create-user.sh', createUserMigration),

    userObsidian: self.createUser('obsidian', 'obsidian-vault', secrets.userObsidian, self.createUserMigration, self.sealedSecret),

    // Ingress orange-proxied por Cloudflare: tls.store default (cloudflare-origin-cert),
    // sin Authelia ni middlewares. Auth la lleva el basic auth nativo de CouchDB.
    ingress_route: u.ingressRoute.from(self.service, 'couchdb.danielramos.me'),

    createUser(name, dbName, password, configMap, secret):: {
      migrationJob: k.batch.v1.job.new('couchdb-create-user-' + name) +
                    k.batch.v1.job.spec.template.spec.withRestartPolicy('OnFailure') +
                    k.batch.v1.job.spec.template.spec.withContainers([
                      container.new('create-user', u.image(versions.curl.image, versions.curl.version)) +
                      container.withCommand(['/bin/sh', '/mnt/scripts/couchdb.create-user.sh']) +
                      container.withEnv(
                        [
                          k.core.v1.envVar.new('USER_NAME', name),
                          k.core.v1.envVar.new('DB_NAME', dbName),
                        ] +
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

      userSecret: u.sealedSecret.forEnv(self.migrationJob, {
        USER_PASSWORD: password,
      }),
    },
  },
}
