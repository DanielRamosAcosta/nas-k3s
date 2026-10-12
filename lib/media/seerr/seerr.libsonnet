local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    deployment: deployment.new('seerr', replicas=1, containers=[
                  container.new('seerr', u.image(versions.seerr.image, versions.seerr.version)) +
                  container.withPorts([containerPort.new('server', 5055)]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv) +
                    u.envVars.fromSealedSecret(self.sealedSecretShared),
                  ) +
                  container.withVolumeMounts([volumeMount.new('config', '/app/config')]) +
                  container.securityContext.withAllowPrivilegeEscalation(false) +
                  container.securityContext.capabilities.withDrop(['ALL']) +
                  u.probes.withStartup.http('/api/v1/settings/public', 5055),
                ]) +
                deployment.spec.template.spec.securityContext.withRunAsUser(1000) +
                deployment.spec.template.spec.securityContext.withRunAsGroup(1000) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath('config', '/data/seerr'),
                ]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      DB_TYPE: 'postgres',
      DB_HOST: 'postgres.databases.svc.cluster.local',
      DB_PORT: '5432',
      DB_USER: 'seerr',
      DB_NAME: 'seerr',
      TZ: 'Europe/Madrid',
    }),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('seerr-shared-sealed-secret', {
      DB_PASS: postgresSecrets.userSeerr,
    }),

    ingressRoute: u.ingressRoute.from(self.service, 'seerr.danielramos.me'),
  },
}
