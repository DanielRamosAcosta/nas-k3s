local argocd = import 'system/argocd/argocd.libsonnet';
local u = import 'utils.libsonnet';

// Import all environments to discover apps dynamically.
// When adding a new environment, add an entry here.
local envs = [
  { namespace: (import '../arr/spec.json').spec.namespace, resources: import '../arr/main.jsonnet' },
  { namespace: (import '../auth/spec.json').spec.namespace, resources: import '../auth/main.jsonnet' },
  { namespace: (import '../databases/spec.json').spec.namespace, resources: import '../databases/main.jsonnet' },
  { namespace: (import '../dashboard/spec.json').spec.namespace, resources: import '../dashboard/main.jsonnet' },
  { namespace: (import '../media/spec.json').spec.namespace, resources: import '../media/main.jsonnet' },
  { namespace: (import '../monitoring/spec.json').spec.namespace, resources: import '../monitoring/main.jsonnet' },
  { namespace: (import '../system/spec.json').spec.namespace, resources: import '../system/main.jsonnet' },
];

// Extract unique app labels from resources in an environment
local discoverApps(env) = std.set([
  env.resources[key][rkey].metadata.labels.app
  for key in std.objectFields(env.resources)
  for rkey in std.objectFields(env.resources[key])
  if std.isObject(env.resources[key][rkey])
     && std.objectHas(std.get(std.get(env.resources[key][rkey], 'metadata', {}), 'labels', {}), 'app')
]);

// Build { appName: namespace } map from all environments
local apps = std.foldl(
  function(acc, env) acc + {
    [app]: env.namespace
    for app in discoverApps(env)
  },
  envs,
  { argocd: 'argocd' },
);

{
  argocd: u.labelApp('argocd', argocd.new(apps)),
}
