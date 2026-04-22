local secrets = import 'crowdsec.secrets.json';
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

        // Enable bidirectional sharing with Crowdsec Central API and
        // the Console. This publishes manual/tainted decisions to the
        // community blocklist so other users benefit.
        'console.yaml': |||
          share_manual_decisions: true
          share_tainted: true
          share_custom: true
          share_context: false
        |||,
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
                name: 'postgres-create-user-crowdsec-sealed-secret',
                key: 'USER_PASSWORD',
              },
            },
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
          // Hub collections installed at startup (the CROWDSEC_COLLECTIONS
          // env var is read by the entrypoint).
          {
            name: 'COLLECTIONS',
            value: 'crowdsecurity/traefik crowdsecurity/linux crowdsecurity/http-cve crowdsecurity/base-http-scenarios crowdsecurity/geoip-enrich',
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
  },
}
