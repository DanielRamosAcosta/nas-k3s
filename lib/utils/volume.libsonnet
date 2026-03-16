local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  fromConfigMap(configMap):: k.core.v1.volume.fromConfigMap(configMap.metadata.name, configMap.metadata.name),
  fromSealedSecret(sealedSecret):: k.core.v1.volume.fromSecret(sealedSecret.metadata.name, sealedSecret.metadata.name),
  fromHostPath(name, path):: k.core.v1.volume.fromHostPath(name, path),
}
