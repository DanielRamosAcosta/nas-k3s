local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'business/facturascripts/facturascripts.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local configPhpTemplate = importstr './facturascripts.config.php';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local configVolumeName = 'config-output',

    statefulSet: statefulSet.new('facturascripts', replicas=1, containers=[
      container.new('facturascripts', u.image(versions.facturascripts.image, versions.facturascripts.version)) +
      container.withPorts([containerPort.new('http', 80)]) +
      container.withEnv([
        k.core.v1.envVar.new('TZ', 'Atlantic/Canary'),
      ]) +
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
    ]) + statefulSet.spec.template.spec.withInitContainers([
      container.new('render-config', u.image(versions.envsubst.image, versions.envsubst.version)) +
      container.withCommand(['sh', '-c', 'envsubst < /mnt/config-template/config.php > /mnt/config/config.php']) +
      container.withEnv(
        u.envVars.fromSealedSecret(self.sealedSecret),
      ) +
      container.withVolumeMounts([
        u.volumeMount.fromFile(self.configTemplate, '/mnt/config-template'),
        volumeMount.new(configVolumeName, '/mnt/config'),
      ]),
    ]) + statefulSet.spec.template.spec.withVolumes([
      volume.fromEmptyDir(configVolumeName),
      volume.fromHostPath('plugins', '/data/facturascripts/plugins'),
      volume.fromHostPath('myfiles', '/cold-data/facturascripts/myfiles'),
      u.volume.fromConfigMap(self.configTemplate),
      u.volume.fromSealedSecret(self.sealedSecret),
    ]),

    service: k.util.serviceFor(self.statefulSet),

    configTemplate: u.configMap.forFile('config.php', configPhpTemplate),

    sealedSecret: u.sealedSecret.wide.forEnvNamed('facturascripts-db', secrets.facturascripts),

    ingressRoute: u.ingressRoute.from(self.service, 'facturas.danielramos.me'),
  },
}
