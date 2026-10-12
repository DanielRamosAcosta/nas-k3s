local argocdLib = import 'github.com/jsonnet-libs/argo-cd-libsonnet/3.2/main.libsonnet';
local app = argocdLib.argoproj.v1alpha1.application;

{
  app(name, path, namespace, repoURL='https://github.com/DanielRamosAcosta/nas-k3s.git', targetRevision='manifests')::
    app.new(name)
    + app.metadata.withNamespace('argocd')
    + app.metadata.withFinalizers(['resources-finalizer.argocd.argoproj.io'])
    + app.spec.withProject('default')
    + app.spec.source.withRepoURL(repoURL)
    + app.spec.source.withTargetRevision(targetRevision)
    + app.spec.source.withPath(path)
    + app.spec.destination.withServer('https://kubernetes.default.svc')
    + app.spec.destination.withNamespace(namespace)
    + app.spec.syncPolicy.withSyncOptions(['ServerSideApply=true', 'CreateNamespace=true'])
    + app.spec.syncPolicy.automated.withPrune(true)
    + app.spec.syncPolicy.automated.withSelfHeal(true),

  appKey(name):: 'app_' + std.strReplace(name, '-', '_'),

  env(spec, resources):: {
    namespace: spec.spec.namespace,
    resources: resources,
  },

  // Extract unique app labels from resources in an environment.
  // Deep-walks to any nesting depth so grouped apps (e.g. { loki: { loki, promtail } })
  // are discovered; stops at the first object with `metadata` (the resource itself).
  discoverApps(env)::
    local collect(node) =
      if !std.isObject(node) then
        []
      else if std.objectHas(node, 'metadata') then
        local labels = std.get(node.metadata, 'labels', {});
        if std.objectHas(labels, 'app') then [labels.app] else []
      else
        std.flattenArrays([collect(node[key]) for key in std.objectFields(node)]);
    std.set(collect(env.resources)),

  // Build { appName: namespace } map from all environments
  buildAppsMap(envs, initial={}):: std.foldl(
    function(acc, env) acc + {
      [app]: env.namespace
      for app in self.discoverApps(env)
    },
    envs,
    initial,
  ),

}
