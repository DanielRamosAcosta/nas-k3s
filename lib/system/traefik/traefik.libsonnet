local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

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
      certificatesResolvers: {
        le: {
          acme: {
            email: 'danielramosacosta1@gmail.com',
            storage: '/data/acme.json',
            httpChallenge: {
              entryPoint: 'web',
            },
          },
        },
      },
      persistence: {
        enabled: true,
        storageClass: 'local-path',
        size: '128Mi',
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
  }),
}
