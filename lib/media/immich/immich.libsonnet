local u = import '../../utils.libsonnet';
local cloudflare = import '../../utils/cloudflare.libsonnet';
local versions = import '../../versions.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local secrets = import 'media/immich/immich.secrets.json';

local immichConfig = importstr './immich.config.json';

{
  local deployment = k.apps.v1.deployment,
  local service = k.core.v1.service,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local this = self,
    deployment: deployment.new('immich', replicas=1, containers=[
                  container.new('immich', u.image(versions.immich.image, versions.immich.version)) +
                  container.withPorts(
                    [containerPort.new('server', 2283)]
                  ) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv) +
                    u.envVars.fromSealedSecret(self.sealedSecretShared),
                  ) +
                  container.withVolumeMounts([
                    volumeMount.new('upload', '/usr/src/app/upload'),
                    volumeMount.new('merged-config', '/app/config') + volumeMount.withReadOnly(true),
                  ]) +
                  u.probes.withStartup.http('/api/server/ping', 2283),
                ]) +
                deployment.spec.template.spec.withInitContainers(
                  container.new('render-config', u.image(versions.envsubst.image, versions.envsubst.version)) +
                  container.withCommand(['sh', '-c', 'envsubst < /data/config.json > /output/immich.json']) +
                  container.withEnv(
                    u.envVars.fromSealedSecret(self.sealedSecret),
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.immichConfigPublic, '/data'),
                    volumeMount.new('merged-config', '/output'),
                  ])
                ) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath('upload', '/cold-data/immich/upload'),
                  u.volume.fromConfigMap(self.immichConfigPublic),
                  volume.fromEmptyDir('merged-config'),
                ]),

    service: k.util.serviceFor(self.deployment) + u.metrics(port='8081'),

    configEnv: u.configMap.forEnv(self.deployment, {
      DB_HOSTNAME: 'postgres.databases.svc.cluster.local',
      DB_USERNAME: 'immich',
      REDIS_HOSTNAME: 'valkey.databases.svc.cluster.local',
      IMMICH_CONFIG_FILE: '/app/config/immich.json',
      IMMICH_TELEMETRY_INCLUDE: 'all',
      IMMICH_LOG_FORMAT: 'json',
      IMMICH_PORT: '2283',
    }),

    sealedSecretShared: u.sealedSecret.wide.forEnvNamed('immich-shared-sealed-secret', {
      DB_PASSWORD: postgresSecrets.userImmich,
    }),

    sealedSecret: u.sealedSecret.forEnv(self.deployment, secrets.immich),

    immichConfigPublic: u.configMap.forFile('config.json', immichConfig),

    // Rate limit against brute-force on /api/auth when photos.danielramos.me is
    // exposed directly (Cloudflare gray cloud, no WAF in front).
    authRateLimit: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: { name: 'immich-auth-ratelimit' },
      spec: {
        rateLimit: {
          average: 2,
          burst: 5,
          period: '1s',
        },
      },
    },

    // Geo-block: only allow requests from ES + CU. Traefik plugin
    // (PascalMinder/geoblock) calls an external geo API per new IP (with
    // an in-memory cache of 1024 entries). Applied to photos only — other
    // services already have geo-block at the Cloudflare edge.
    // Crowdsec bouncer: in-band lookup against the in-cluster LAPI.
    // Blocks IPs with an active Crowdsec decision (community blocklist
    // + whatever the agent has detected from Traefik logs). The API
    // key is read from a file mounted into the Traefik pod, not from
    // the Middleware spec itself, so it never lands in git.
    crowdsecBouncer: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: { name: 'immich-crowdsec-bouncer' },
      spec: {
        plugin: {
          bouncer: {
            enabled: true,
            logLevel: 'INFO',
            // `stream` mode caches LAPI decisions locally and refreshes
            // every `updateIntervalSeconds` instead of calling LAPI on
            // every request (cheap per-hit, slight lag picking up new
            // bans). For photo browsing on a homelab this is the right
            // trade-off.
            crowdsecMode: 'stream',
            updateIntervalSeconds: 60,
            crowdsecLapiScheme: 'http',
            crowdsecLapiHost: 'crowdsec-service.system.svc.cluster.local:8080',
            crowdsecLapiKeyFile: '/etc/crowdsec-bouncer/BOUNCER_KEY',
            forwardedHeadersTrustedIPs: cloudflare.allCidrs,
          },
        },
      },
    },

    geoBlockEsCu: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'Middleware',
      metadata: { name: 'immich-geoblock-es-cu' },
      spec: {
        plugin: {
          geoblock: {
            silentStartUp: false,
            // `allowLocalRequests: false` is intentional. Combined with
            // Traefik's `externalTrafficPolicy: Local`, the plugin now
            // sees the real client IP (not the k3s CNI gateway), so
            // there's no reason to blanket-allow private ranges.
            allowLocalRequests: false,
            logLocalRequests: true,
            logAllowedRequests: false,
            logApiRequests: false,
            api: 'https://get.geojs.io/v1/ip/country/{ip}',
            apiTimeoutMs: 500,
            cacheSize: 1024,
            forceMonthlyUpdate: true,
            allowUnknownCountries: false,
            unknownCountryApiResponse: 'nil',
            countries: ['ES', 'CU'],
          },
        },
      },
    },

    // Both the main route and the /api/auth route carry the same
    // baseline defenses (geo-block + Crowdsec bouncer). The auth route
    // adds a stricter rate limit on top.
    local baselineMiddlewares = [
      { name: this.geoBlockEsCu.metadata.name },
      { name: this.crowdsecBouncer.metadata.name },
    ],
    local authRoute = {
      match: 'Host(`photos.danielramos.me`) && PathPrefix(`/api/auth`)',
      kind: 'Rule',
      services: [{ name: this.service.metadata.name, port: this.service.spec.ports[0].port }],
      middlewares: baselineMiddlewares + [
        { name: this.authRateLimit.metadata.name },
      ],
    },
    ingressRoute: u.ingressRoute.from(
      self.service,
      'photos.danielramos.me',
      baselineMiddlewares,
      [authRoute],
    ),

    // Machine Learning Service
    mlDeployment: deployment.new('immich-machine-learning', replicas=1, containers=[
                    container.new('immich-machine-learning', u.image(versions.immichMl.image, versions.immichMl.version)) +
                    container.withPorts([
                      containerPort.new('http', 3003),
                    ]) +
                    container.withEnv(
                      u.envVars.fromConfigMap(self.mlConfigEnv),
                    ) +
                    container.withVolumeMounts([
                      volumeMount.new('model-cache', '/cache'),
                    ]) +
                    {
                      resources: {
                        requests: {
                          memory: '2Gi',
                          cpu: '1000m',
                        },
                        limits: {
                          memory: '6Gi',
                          cpu: '4000m',
                        },
                      },
                    } +
                    u.probes.withStartup.http('/ping', 3003),
                  ]) +
                  deployment.spec.template.spec.withVolumes([
                    volume.fromHostPath('model-cache', '/data/immich/ml-cache'),
                  ]) +
                  deployment.spec.template.spec.withEnableServiceLinks(false) +
                  deployment.spec.strategy.withType('Recreate'),

    mlConfigEnv: u.configMap.forEnv(self.mlDeployment, {
      TRANSFORMERS_CACHE: '/cache',
      PYTHONUNBUFFERED: '1',
    }),

    mlService: k.util.serviceFor(self.mlDeployment),

  },
}
