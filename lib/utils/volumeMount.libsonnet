local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  fromFile(configMapOrSecret, path):: k.core.v1.volumeMount.new(configMapOrSecret.metadata.name, path + '/' + std.objectFieldsAll(configMapOrSecret.data)[0]) + k.core.v1.volumeMount.withSubPath(std.objectFieldsAll(configMapOrSecret.data)[0]),
  fromSealedSecretFile(sealedSecret, path):: k.core.v1.volumeMount.new(sealedSecret.metadata.name, path + '/' + std.objectFields(sealedSecret.spec.encryptedData)[0]) + k.core.v1.volumeMount.withSubPath(std.objectFields(sealedSecret.spec.encryptedData)[0]),
}
