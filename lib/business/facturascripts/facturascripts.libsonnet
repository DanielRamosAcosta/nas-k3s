local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'business/facturascripts/facturascripts.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local configPhpTemplate = importstr './facturascripts.config.php';

{
  local deployment = k.apps.v1.deployment,
  local cronJob = k.batch.v1.cronJob,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local configVolumeName = 'config-output',

    deployment: deployment.new('facturascripts', replicas=1, containers=[
      container.new('facturascripts', u.image(versions.facturascripts.image, versions.facturascripts.version)) +
      container.withPorts([containerPort.new('http', 80)]) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv),
      ) +
      container.withVolumeMounts([
        volumeMount.new(configVolumeName, '/var/www/html/config.php') + volumeMount.withSubPath('config.php'),
        volumeMount.new('plugins', '/var/www/html/Plugins'),
        volumeMount.new('myfiles', '/var/www/html/MyFiles'),
      ]) +
      container.withCommand(['bash', '-c', |||
        # Copy app source to webroot (same as official entrypoint)
        if [ ! -f /var/www/html/.htaccess ]; then
          cp -r /usr/src/facturascripts/* /var/www/html/
          cp /var/www/html/htaccess-sample /var/www/html/.htaccess
          chmod -R o+w /var/www/html
        fi
        exec apache2-foreground
      |||]) +
      u.probes.withStartup.http('/deploy', 80),
    ]) + deployment.spec.template.spec.withInitContainers([
      container.new('render-config', u.image(versions.envsubst.image, versions.envsubst.version)) +
      container.withCommand(['sh', '-c', 'envsubst < /mnt/config-template/config.php > /mnt/config/config.php']) +
      container.withEnv(
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      container.withVolumeMounts([
        u.volumeMount.fromFile(self.configTemplate, '/mnt/config-template'),
        volumeMount.new(configVolumeName, '/mnt/config'),
      ]),
    ]) + deployment.spec.template.spec.withVolumes([
      volume.fromEmptyDir(configVolumeName),
      volume.fromHostPath('plugins', '/data/facturascripts/plugins'),
      volume.fromHostPath('myfiles', '/data/facturascripts/myfiles'),
      u.volume.fromConfigMap(self.configTemplate),
      u.volume.fromSealedSecret(self.sealedSecret),
    ]),

    service: k.util.serviceFor(self.deployment),

    configTemplate: u.configMap.forFile('config.php', configPhpTemplate),

    configEnv: u.configMap.forEnv(self.deployment, {
      TZ: 'Atlantic/Canary',
      APACHE_RUN_USER: '#1000',
      APACHE_RUN_GROUP: '#1000',
    }),

    sealedSecret: u.sealedSecret.wide.forEnvNamed('facturascripts-db', secrets.facturascripts),

    ingressRoute: u.ingressRoute.from(self.service, 'facturas.danielramos.me'),

    // Sync MyFiles from SSD to HDD daily at 3 AM
    myfilesBackupCron: cronJob.new(
                         name='facturascripts-myfiles-backup',
                         schedule='0 3 * * *',
                         containers=[
                           container.new('rsync', u.image(versions.rsync.image, versions.rsync.version)) +
                           container.withCommand(['sh', '-c', |||
                             rsync -a --delete \
                               --exclude='Cache/' \
                               --exclude='Tmp/' \
                               --exclude='routes.json' \
                               --exclude='.snapshots/' \
                               /mnt/source/ /mnt/dest/
                           |||]) +
                           container.withVolumeMounts([
                             volumeMount.new('source', '/mnt/source', true),
                             volumeMount.new('dest', '/mnt/dest'),
                           ]),
                         ]
                       ) +
                       cronJob.spec.jobTemplate.spec.template.spec.securityContext.withRunAsUser(1000) +
                       cronJob.spec.jobTemplate.spec.template.spec.securityContext.withRunAsGroup(1000) +
                       cronJob.spec.jobTemplate.spec.template.spec.withRestartPolicy('OnFailure') +
                       cronJob.spec.withConcurrencyPolicy('Forbid') +
                       cronJob.spec.withSuccessfulJobsHistoryLimit(3) +
                       cronJob.spec.withFailedJobsHistoryLimit(3) +
                       cronJob.spec.jobTemplate.spec.template.spec.withVolumes([
                         volume.fromHostPath('source', '/data/facturascripts/myfiles'),
                         volume.fromHostPath('dest', '/cold-data/contabilidad'),
                       ]),
  },
}
