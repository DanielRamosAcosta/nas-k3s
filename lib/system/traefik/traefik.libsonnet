local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local secrets = import 'traefik.secrets.json';
local u = import 'utils.libsonnet';
local cloudflare = import 'utils/cloudflare.libsonnet';

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
        // Crowdsec detection).
        '--entryPoints.websecure.forwardedHeaders.trustedIPs=' + std.join(',', cloudflare.allCidrs),
        '--entryPoints.web.forwardedHeaders.trustedIPs=' + std.join(',', cloudflare.allCidrs),
      ],
      // Community plugins loaded by Traefik.
      //   - `geoblock` provides synchronous country-based filtering.
      //   - `bouncer` consults Crowdsec LAPI to block IPs with active
      //     decisions (community blocklist + locally-detected attacks).
      experimental: {
        plugins: {
          geoblock: {
            moduleName: 'github.com/PascalMinder/geoblock',
            version: 'v0.3.7',
          },
          bouncer: {
            moduleName: 'github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin',
            version: 'v1.5.1',
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
          {
            // Crowdsec bouncer API key, shared with the LAPI via
            // a SealedSecret in the `system` namespace. The plugin
            // reads the key from this file (crowdsecLapiKeyFile in
            // the Middleware CR), keeping it out of ConfigMap/CR YAML.
            name: 'crowdsec-bouncer-key',
            secret: { secretName: 'crowdsec-bouncer-key' },
          },
        ],
      },
      additionalVolumeMounts: [
        {
          name: 'acme',
          mountPath: '/data',
        },
        {
          name: 'crowdsec-bouncer-key',
          mountPath: '/etc/crowdsec-bouncer',
          readOnly: true,
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
