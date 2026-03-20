local core = import 'utils/core.libsonnet';

{
  // Strict scope (default) — secrets bound to namespace+name
  forEnv(component, encryptedData):: {
    apiVersion: 'bitnami.com/v1alpha1',
    kind: 'SealedSecret',
    metadata: {
      name: component.metadata.name + '-sealed-secret',
    },
    spec: {
      encryptedData: encryptedData,
    },
  },
  forEnvNamed(name, encryptedData):: {
    apiVersion: 'bitnami.com/v1alpha1',
    kind: 'SealedSecret',
    metadata: {
      name: name,
    },
    spec: {
      encryptedData: encryptedData,
    },
  },
  forTls(name, encryptedData):: {
    apiVersion: 'bitnami.com/v1alpha1',
    kind: 'SealedSecret',
    metadata: {
      name: name,
    },
    spec: {
      template: { type: 'kubernetes.io/tls' },
      encryptedData: encryptedData,
    },
  },
  forFile(fileName, encryptedValue):: {
    apiVersion: 'bitnami.com/v1alpha1',
    kind: 'SealedSecret',
    metadata: {
      name: core.normalizeName(fileName) + '-sealed-secret',
    },
    spec: {
      encryptedData: {
        [fileName]: encryptedValue,
      },
    },
  },

  // Cluster-wide scope — shared secrets (DB passwords, SMTP, etc.)
  wide: {
    forEnv(component, encryptedData):: {
      apiVersion: 'bitnami.com/v1alpha1',
      kind: 'SealedSecret',
      metadata: {
        name: component.metadata.name + '-sealed-secret',
        annotations: {
          'sealedsecrets.bitnami.com/cluster-wide': 'true',
        },
      },
      spec: {
        encryptedData: encryptedData,
      },
    },
    forEnvNamed(name, encryptedData):: {
      apiVersion: 'bitnami.com/v1alpha1',
      kind: 'SealedSecret',
      metadata: {
        name: name,
        annotations: {
          'sealedsecrets.bitnami.com/cluster-wide': 'true',
        },
      },
      spec: {
        encryptedData: encryptedData,
      },
    },
    forFile(fileName, encryptedValue):: {
      apiVersion: 'bitnami.com/v1alpha1',
      kind: 'SealedSecret',
      metadata: {
        name: core.normalizeName(fileName) + '-sealed-secret',
        annotations: {
          'sealedsecrets.bitnami.com/cluster-wide': 'true',
        },
      },
      spec: {
        encryptedData: {
          [fileName]: encryptedValue,
        },
      },
    },
  },
}
