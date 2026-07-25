local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local secrets = import 'games/minecraft/minecraft.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    statefulSet: statefulSet.new('minecraft', replicas=1, containers=[
                   container.new('minecraft', u.image(versions.minecraft.image, versions.minecraft.version)) +
                   container.withPorts([
                     containerPort.new('minecraft', 25565),
                     containerPort.new('rcon', 25575),
                   ]) +
                   container.withEnv(
                     u.envVars.fromConfigMap(self.configEnv) +
                     u.envVars.fromSealedSecret(self.sealedSecret)
                   ) +
                   container.withVolumeMounts([
                     volumeMount.new('data', '/data'),
                     volumeMount.new('tmp', '/tmp'),
                   ]) +
                   {
                     resources: {
                       requests: { memory: '6Gi', cpu: '1' },
                       limits: { memory: '6Gi' },
                     },
                   } +
                   {
                     securityContext: {
                       readOnlyRootFilesystem: true,
                       allowPrivilegeEscalation: false,
                       capabilities: { drop: ['ALL'] },
                       seccompProfile: { type: 'RuntimeDefault' },
                     },
                   } +
                   {
                     lifecycle: {
                       preStop: { exec: { command: ['/bin/sh', '-c', 'touch /data/.paused'] } },
                       postStart: { exec: { command: ['/bin/sh', '-c', 'rm -f /data/.paused'] } },
                     },
                   } +
                   u.probes.stateful.tcp(25565),
                 ]) +
                 statefulSet.spec.withServiceName('minecraft') +
                 statefulSet.spec.template.spec.withTerminationGracePeriodSeconds(90) +
                 statefulSet.spec.template.spec.securityContext.withRunAsNonRoot(true) +
                 statefulSet.spec.template.spec.securityContext.withRunAsUser(1000) +
                 statefulSet.spec.template.spec.securityContext.withRunAsGroup(1000) +
                 statefulSet.spec.template.spec.withVolumes([
                   volume.fromHostPath('data', '/data/minecraft'),
                   volume.fromEmptyDir('tmp'),
                 ]) +
                 { spec+: { replicas:: null } },

    service: k.util.serviceFor(self.statefulSet, nameFormat='%(port)s') +
             { metadata+: { annotations+: { 'mc-router.itzg.me/defaultServer': 'true' } } },

    sealedSecret: u.sealedSecret.forEnvNamed('minecraft-rcon', secrets.minecraftRcon),

    configEnv: u.configMap.forEnv(self.statefulSet, {
      EULA: 'TRUE',
      TYPE: 'PAPER',
      VERSION: versions.minecraft.paperVersion,
      PAPER_BUILD: versions.minecraft.paperBuild,
      PAPER_CHANNEL: 'experimental',
      MEMORY: '4G',
      USE_AIKAR_FLAGS: 'true',
      ONLINE_MODE: 'TRUE',
      OPS: 'Duning',
      EXISTING_OPS_FILE: 'SYNCHRONIZE',
      DIFFICULTY: 'hard',
      MOTD: '§c§lE§6§ls§e§lc§a§lr§b§lo§9§lt§d§lo§c§ln§6§le§e§lt§a§la',
      MODRINTH_PROJECTS: 'squaremap',
      RCON_PORT: '25575',
      TZ: 'Atlantic/Canary',
    }),
  },
}
