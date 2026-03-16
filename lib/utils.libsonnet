local core = import 'utils/core.libsonnet';
local pv = import 'utils/pv.libsonnet';
local pvc = import 'utils/pvc.libsonnet';
local volume = import 'utils/volume.libsonnet';
local volumeMountMod = import 'utils/volumeMount.libsonnet';
local sealedSecret = import 'utils/sealedSecret.libsonnet';
local configMap = import 'utils/configMap.libsonnet';
local envVars = import 'utils/envVars.libsonnet';
local ingressRoute = import 'utils/ingressRoute.libsonnet';
local rbac = import 'utils/rbac.libsonnet';
local prometheusMod = import 'utils/prometheus.libsonnet';
local command = import 'utils/command.libsonnet';
local files = import 'utils/files.libsonnet';
local probes = import 'utils/probes.libsonnet';

{
  // Core helpers
  image:: core.image,
  labelApp:: core.labelApp,
  withoutSchema:: core.withoutSchema,

  // File helpers
  injectFiles:: files.injectFiles,
  injectFile:: files.injectFile,

  // Domain modules
  pv: pv,
  pvc: pvc,
  volume: volume,
  volumeMount: volumeMountMod,
  sealedSecret: sealedSecret,
  configMap: configMap,
  envVars: envVars,
  ingressRoute: ingressRoute,
  rbac(name, namespace, rules):: rbac.new(name, namespace, rules),
  prometheus(port, path='/metrics'):: prometheusMod.annotations(port, path),
  command: command,
  probes: probes,
}
