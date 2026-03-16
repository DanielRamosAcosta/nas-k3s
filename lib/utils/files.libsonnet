local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  injectFiles(configMapOrSecrets):: k.apps.v1.deployment.spec.template.spec.withVolumes([
    if resource.kind == 'Secret' || resource.kind == 'SealedSecret' then
      k.core.v1.volume.fromSecret(resource.metadata.name, resource.metadata.name)
    else
      k.core.v1.volume.fromConfigMap(resource.metadata.name, resource.metadata.name)
    for resource in configMapOrSecrets
  ]),
  injectFile(resource)::
    if resource.kind == 'Secret' || resource.kind == 'SealedSecret' then
      k.core.v1.volume.fromSecret(resource.metadata.name, resource.metadata.name)
    else
      k.core.v1.volume.fromConfigMap(resource.metadata.name, resource.metadata.name)
  ,
}
