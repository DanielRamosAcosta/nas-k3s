local secrets = import 'crowdsec.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local u = import 'utils.libsonnet';

local helm = tanka.helm.new(std.thisFile);

// Crowdsec agent + LAPI. Bouncer (Traefik plugin) wiring happens in a
// separate follow-up once we've generated the bouncer API key from the
// running LAPI pod (see NASKS-53 Phase 2).
//
// Phase 1 (this module): agent detects attacks via Loki acquisition of
// Traefik logs + enrichment with MaxMind GeoLite2. Decisions stored in
// Postgres (shared db with Immich/Authelia/etc.). Community blocklist
// sync + Crowdsec Console enrollment.
{
  new():: helm.template('crowdsec', '../../../charts/crowdsec', {
    namespace: 'system',
    values: {
      // We don't run cert-manager, so disable mTLS between agent↔lapi.
      // Both live in the same namespace, traffic stays inside the cluster.
      tls: { enabled: false },

      // --- Shared config (mounted into agent + lapi) -----------------------

      config: {
        // Base config.yaml.local merged with the image default. Adds
        // Postgres backend + keeps the chart's auto_registration block
        // (agent ↔ lapi auto-registration).
        'config.yaml.local': |||
          api:
            server:
              auto_registration:
                enabled: true
                token: "${REGISTRATION_TOKEN}"
                allowed_ranges:
                  - "127.0.0.1/32"
                  - "10.0.0.0/8"
                  - "172.16.0.0/12"
                  - "192.168.0.0/16"
          db_config:
            type:     postgresql
            user:     crowdsec
            password: ${DB_PASSWORD}
            db_name:  crowdsec
            host:     postgres.databases.svc.cluster.local
            port:     5432
            sslmode:  disable
        |||,

        // NB: we intentionally do NOT render `console.yaml` here. The
        // chart mounts it read-only from the ConfigMap, which breaks
        // `cscli console enroll` at container start. We let Crowdsec
        // manage that file itself — sharing flags default to sane
        // values (share_manual_decisions + share_tainted on).
      },

      // --- LAPI ------------------------------------------------------------

      lapi: {
        replicas: 1,
        // Store API credentials in Secrets so LAPI is effectively stateless.
        // No local PVCs needed — all durable state lives in Postgres.
        persistentVolume: {
          data: { enabled: false },
          config: { enabled: false },
        },
        storeCAPICredentialsInSecret: true,
        storeLAPICscliCredentialsInSecret: true,

        env: [
          {
            name: 'DB_PASSWORD',
            valueFrom: {
              secretKeyRef: {
                // Cluster-wide sealed secret — the one in databases/ is
                // only decrypted in that namespace, so we mirror it here
                // (see postgresPasswordSealedSecret below).
                name: 'crowdsec-postgres-password',
                key: 'USER_PASSWORD',
              },
            },
          },
          // Console enrollment: the chart's docker_start.sh reads
          // ENROLL_KEY / ENROLL_INSTANCE_NAME and runs
          // `cscli console enroll --name $INSTANCE $KEY` on startup,
          // registering this machine against app.crowdsec.net.
          { name: 'ENROLL_INSTANCE_NAME', value: 'nas-k3s' },
          {
            name: 'ENROLL_KEY',
            valueFrom: { secretKeyRef: { name: 'crowdsec-console', key: 'CROWDSEC_CONSOLE_ENROLLMENT_KEY' } },
          },
          // Pre-register the Traefik bouncer with a known key. The
          // entrypoint iterates BOUNCER_KEY_* env vars and runs
          // `cscli bouncers add` for each. The plugin reads the same
          // key from a mounted Secret in the Traefik pod (see
          // traefik.libsonnet).
          {
            name: 'BOUNCER_KEY_traefik',
            valueFrom: { secretKeyRef: { name: 'crowdsec-bouncer-key', key: 'BOUNCER_KEY' } },
          },
        ],

        // Expose /metrics on 6060 (scraped by VictoriaMetrics — follow-up).
        metrics: {
          enabled: true,
          serviceMonitor: { enabled: false },
          podMonitor: { enabled: false },
        },

        resources: {
          requests: { cpu: '100m', memory: '200Mi' },
          limits: { cpu: '500m', memory: '500Mi' },
        },
      },

      // --- Agent -----------------------------------------------------------

      agent: {
        // Stateless: config is pulled on startup, decisions in Postgres.
        persistentVolume: {
          data: { enabled: false },
          config: { enabled: false },
        },

        // `acquisition` (the chart's k8s-native pod log tail) is unused;
        // we pull logs from Loki instead via `additionalAcquisition`.
        acquisition: [],
        // Loki acquisition: pull Traefik access logs via LogQL from the
        // monitoring Loki instance. Type=traefik lets crowdsec's Traefik
        // parser match the stream.
        additionalAcquisition: [
          {
            source: 'loki',
            url: 'http://loki.monitoring.svc.cluster.local:3100/',
            query: '{namespace="system",pod=~"traefik-.*"}',
            labels: { type: 'traefik' },
          },
        ],

        env: [
          // Hub collections (bundles of parsers + scenarios) installed
          // at startup by the image entrypoint.
          {
            name: 'COLLECTIONS',
            value: 'crowdsecurity/traefik crowdsecurity/linux crowdsecurity/http-cve crowdsecurity/base-http-scenarios',
          },
          // Parsers: geoip-enrich tags events with country info, used by
          // scenarios that can filter/ban on country. It's a parser, not
          // a collection, so it goes in PARSERS.
          {
            name: 'PARSERS',
            value: 'crowdsecurity/geoip-enrich',
          },
          // MaxMind GeoLite2-Country for the geoip-enrich parser.
          // Credentials are passed to geoipupdate at DB refresh time.
          {
            name: 'MAXMIND_ACCOUNT_ID',
            valueFrom: { secretKeyRef: { name: 'crowdsec-maxmind', key: 'MAXMIND_ACCOUNT_ID' } },
          },
          {
            name: 'MAXMIND_LICENCE_KEY',
            valueFrom: { secretKeyRef: { name: 'crowdsec-maxmind', key: 'MAXMIND_LICENCE_KEY' } },
          },
        ],

        resources: {
          requests: { cpu: '100m', memory: '150Mi' },
          limits: { cpu: '500m', memory: '300Mi' },
        },
      },
    },
  }) + {
    maxmindSealedSecret: u.sealedSecret.forEnvNamed('crowdsec-maxmind', {
      MAXMIND_ACCOUNT_ID: secrets.maxmindAccountId,
      MAXMIND_LICENCE_KEY: secrets.maxmindLicenceKey,
    }),
    // Console enrollment key — referenced by a post-deploy manual step:
    //   kubectl exec -n system deploy/crowdsec-lapi -- \
    //     cscli console enroll --name nas-k3s $CROWDSEC_CONSOLE_ENROLLMENT_KEY
    // Once Phase 2 wires a postStart hook, this becomes automatic.
    consoleEnrollmentSealedSecret: u.sealedSecret.forEnvNamed('crowdsec-console', {
      CROWDSEC_CONSOLE_ENROLLMENT_KEY: secrets.crowdsecConsoleEnrollmentKey,
    }),
    // Bouncer API key shared between Crowdsec LAPI (pre-registration
    // via BOUNCER_KEY_traefik env) and the Traefik bouncer plugin
    // (mounted as a file, read via `crowdsecLapiKeyFile`).
    bouncerKeySealedSecret: u.sealedSecret.forEnvNamed('crowdsec-bouncer-key', {
      BOUNCER_KEY: secrets.bouncerKey,
    }),
    // Mirror the cluster-wide Postgres password for the `crowdsec` DB
    // user into the system namespace so LAPI can mount it as env.
    postgresPasswordSealedSecret: u.sealedSecret.wide.forEnvNamed('crowdsec-postgres-password', {
      USER_PASSWORD: postgresSecrets.userCrowdsec,
    }),
  },
}
