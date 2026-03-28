local argocdUtil = import 'utils/argocd.libsonnet';
local command = import 'utils/command.libsonnet';
local configMap = import 'utils/configMap.libsonnet';
local core = import 'utils/core.libsonnet';
local envVars = import 'utils/envVars.libsonnet';
local files = import 'utils/files.libsonnet';
local ingressRoute = import 'utils/ingressRoute.libsonnet';
local labels = import 'utils/labels.libsonnet';
local metricsMod = import 'utils/metrics.libsonnet';
local probes = import 'utils/probes.libsonnet';
local rbac = import 'utils/rbac.libsonnet';
local sealedSecret = import 'utils/sealedSecret.libsonnet';
local volume = import 'utils/volume.libsonnet';
local volumeMountMod = import 'utils/volumeMount.libsonnet';

{
  Environment(apps):: {
    [core.kebabCase(name)]: core.labelApp(core.kebabCase(name), apps[name])
    for name in std.objectFields(apps)
  },

  image:: core.image,
  labelApp:: core.labelApp,
  withoutSchema:: core.withoutSchema,

  // File helpers
  injectFiles:: files.injectFiles,
  injectFile:: files.injectFile,

  // Domain modules
  volume: volume,
  volumeMount: volumeMountMod,
  sealedSecret: sealedSecret,
  configMap: configMap,
  envVars: envVars,
  labels: labels,
  ingressRoute: ingressRoute,
  rbac(name, namespace, rules):: rbac.new(name, namespace, rules),
  metrics(port, path='/metrics'):: metricsMod.annotations(port, path),
  argocd: argocdUtil,
  command: command,
  probes: probes,
}
