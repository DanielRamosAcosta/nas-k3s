local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local secrets = import 'traefik.secrets.json';

local helm = tanka.helm.new(std.thisFile);

{
  new():: helm.template('traefik', '../../../charts/traefik', {
    namespace: 'system',
    values: {
      priorityClassName: 'system-cluster-critical',
      tolerations: [
        {
          key: 'CriticalAddonsOnly',
          operator: 'Exists',
        },
        {
          key: 'node-role.kubernetes.io/control-plane',
          operator: 'Exists',
          effect: 'NoSchedule',
        },
      ],
      ports: {
        metrics: {
          port: 9100,
          expose: { default: false },
        },
        web: {
          http: {
            redirections: {
              entryPoint: {
                to: 'websecure',
                scheme: 'https',
              },
            },
          },
        },
        websecure: {
          http: {
            tls: {
              enabled: true,
            },
          },
        },
      },
      metrics: {
        prometheus: {
          entryPoint: 'metrics',
        },
      },
      logs: {
        general: {
          level: 'INFO',
        },
      },
      providers: {
        kubernetesCRD: {
          enabled: true,
          allowEmptyServices: true,
        },
        kubernetesIngress: {
          enabled: true,
          allowEmptyServices: true,
          publishedService: {
            enabled: true,
          },
        },
      },
      persistence: {
        enabled: false,
      },
      service: {
        type: 'LoadBalancer',
        ipFamilyPolicy: 'PreferDualStack',
      },
      ingressClass: {
        enabled: true,
        isDefaultClass: true,
      },
    },
  }) + {
    sealed_secret: {
      apiVersion: 'bitnami.com/v1alpha1',
      kind: 'SealedSecret',
      metadata: {
        name: 'cloudflare-origin-cert',
      },
      spec: {
        template: {
          type: 'kubernetes.io/tls',
        },
        encryptedData: secrets.cloudflareOriginCert,
      },
    },
    tls_store: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'TLSStore',
      metadata: {
        name: 'default',
        namespace: 'system',
      },
      spec: {
        defaultCertificate: {
          secretName: 'cloudflare-origin-cert',
        },
      },
    },
  },
}
