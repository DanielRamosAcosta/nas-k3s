local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local extractConfig(configMapName, keys) = [
    k.core.v1.envVar.withName(key) +
    k.core.v1.envVar.valueFrom.configMapKeyRef.withKey(key) +
    k.core.v1.envVar.valueFrom.configMapKeyRef.withName(configMapName)
    for key in keys
  ],

  local secretRef(secretName, key) = k.core.v1.envVar.fromSecretRef(key, secretName, key),

  local extractSecrets(secretName, keys) = [
    secretRef(secretName, key)
    for key in keys
  ],

  fromConfigMap(configMap):: extractConfig(configMap.metadata.name, std.objectFieldsAll(configMap.data)),
  fromSealedSecret(sealedSecret):: extractSecrets(sealedSecret.metadata.name, std.objectFields(sealedSecret.spec.encryptedData)),
}
