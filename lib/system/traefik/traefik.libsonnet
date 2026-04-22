local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local secrets = import 'traefik.secrets.json';
local u = import 'utils.libsonnet';

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
      // Let's Encrypt ACME resolver (DNS-01 via Cloudflare API).
      // Used only by services on gray cloud (e.g. photos.danielramos.me).
      // Orange-proxied services keep the default TLSStore (cloudflare-origin-cert).
      additionalArguments: [
        '--certificatesresolvers.letsencrypt.acme.email=danielramosacosta1@gmail.com',
        '--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json',
        '--certificatesresolvers.letsencrypt.acme.dnschallenge=true',
        '--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=cloudflare',
      ],
      env: [
        {
          name: 'CF_DNS_API_TOKEN',
          valueFrom: {
            secretKeyRef: {
              name: 'traefik-cf-dns-api-token',
              key: 'CF_DNS_API_TOKEN',
            },
          },
        },
      ],
      // The chart always creates a volume named `persistence.name` mounted at
      // `persistence.path`. We park its default emptyDir at /var/unused and
      // mount our real hostPath-backed /data via additionalVolumes below, so
      // acme.json persists across pod restarts under /data/traefik on the NAS.
      persistence: {
        enabled: false,
        name: 'unused-data',
        path: '/var/unused',
      },
      deployment+: {
        additionalVolumes: [
          {
            name: 'acme',
            hostPath: {
              path: '/data/traefik',
              type: 'DirectoryOrCreate',
            },
          },
        ],
      },
      additionalVolumeMounts: [
        {
          name: 'acme',
          mountPath: '/data',
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
          // TEMPORARY: DEBUG while diagnosing ACME DNS-01 for photos.danielramos.me.
          // Revert to INFO once the letsencrypt cert is obtained and stable.
          level: 'DEBUG',
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
    sealedSecret: u.sealedSecret.forTls('cloudflare-origin-cert', secrets.cloudflareOriginCert),
    tls_store: u.ingressRoute.tlsStore(self.sealedSecret),
    cfDnsApiTokenSealedSecret: u.sealedSecret.forEnvNamed('traefik-cf-dns-api-token', {
      CF_DNS_API_TOKEN: secrets.cfDnsApiToken,
    }),
  },
}
