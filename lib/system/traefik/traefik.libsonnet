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
        // Trust Cloudflare edges as proxies so X-Forwarded-For reflects the
        // real client IP for orange-proxied hostnames (logs, rate limits,
        // Crowdsec detection). IPs from cloudflare.com/ips-v4 + ips-v6.
        '--entryPoints.websecure.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32',
        '--entryPoints.web.forwardedHeaders.trustedIPs=173.245.48.0/20,103.21.244.0/22,103.22.200.0/22,103.31.4.0/22,141.101.64.0/18,108.162.192.0/18,190.93.240.0/20,188.114.96.0/20,197.234.240.0/22,198.41.128.0/17,162.158.0.0/15,104.16.0.0/13,104.24.0.0/14,172.64.0.0/13,131.0.72.0/22,2400:cb00::/32,2606:4700::/32,2803:f800::/32,2405:b500::/32,2405:8100::/32,2a06:98c0::/29,2c0f:f248::/32',
      ],
      // Community plugins loaded by Traefik. GeoBlock provides synchronous
      // country-based filtering (applied per-route via Middleware CR).
      // Crowdsec bouncer plugin will be added in Phase 2 of NASKS-53.
      experimental: {
        plugins: {
          geoblock: {
            moduleName: 'github.com/PascalMinder/geoblock',
            version: 'v0.3.7',
          },
        },
      },
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
      service: {
        type: 'LoadBalancer',
        ipFamilyPolicy: 'PreferDualStack',
        // Preserve the real client IP at the Traefik container. k3s's
        // default Cluster policy SNATs incoming traffic to the node
        // CNI gateway (10.42.0.1), which breaks per-IP middlewares
        // like the GeoBlock plugin and Crowdsec's IP-based scenarios.
        // On a single-node NAS `Local` has no traffic distribution
        // downside.
        spec: { externalTrafficPolicy: 'Local' },
      },
      ingressClass: {
        enabled: true,
        isDefaultClass: true,
      },
    },
  }) + {
    // TLSStore default now uses a Let's Encrypt-generated wildcard cert
    // (`*.danielramos.me` + apex) via the letsencrypt resolver. This replaces
    // the previous Cloudflare Origin Cert so that:
    //   - Orange-proxied services keep working (CF strict accepts publicly
    //     trusted certs, LE included).
    //   - Gray-cloud services (e.g. photos.danielramos.me) get a browser-
    //     trusted cert without per-route certResolver tricks (Traefik was
    //     short-circuiting LE emission when a wildcard matched the SNI).
    tls_store: u.ingressRoute.tlsStoreGenerated(
      'letsencrypt',
      'danielramos.me',
      ['*.danielramos.me'],
    ),
    cfDnsApiTokenSealedSecret: u.sealedSecret.forEnvNamed('traefik-cf-dns-api-token', {
      CF_DNS_API_TOKEN: secrets.cfDnsApiToken,
    }),
    // Legacy CF Origin cert kept in SealedSecrets for quick rollback; not
    // referenced by any resource currently. Can be removed after LE wildcard
    // has been stable for a few weeks.
    legacyCloudflareOriginSealedSecret: u.sealedSecret.forTls(
      'cloudflare-origin-cert',
      secrets.cloudflareOriginCert,
    ),
  },
}
