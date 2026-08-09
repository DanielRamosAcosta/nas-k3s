local secrets = import 'crowdsec.secrets.json';
local postgresSecrets = import 'databases/postgres/postgres.secrets.json';
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local u = import 'utils.libsonnet';

local helm = tanka.helm.new(std.thisFile);
local crowdsecConfig = importstr './config.yaml';
local couchDbConfig = importstr './couchdb-http-auth-bf.yaml';

{
  new():: helm.template('crowdsec', '../../../charts/crowdsec', {
    namespace: 'system',
    values: {
      tls: { enabled: false },
      config: {
        'config.yaml.local': crowdsecConfig,
        scenarios: {
          'couchdb-http-auth-bf.yaml': couchDbConfig,
        },
      },
      lapi: {
        replicas: 1,
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
                name: 'crowdsec-postgres-password',
                key: 'USER_PASSWORD',
              },
            },
          },
          { name: 'ENROLL_INSTANCE_NAME', value: 'nas-k3s' },
          {
            name: 'ENROLL_KEY',
            valueFrom: { secretKeyRef: { name: 'crowdsec-console', key: 'CROWDSEC_CONSOLE_ENROLLMENT_KEY' } },
          },
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
        persistentVolume: {
          data: { enabled: false },
          config: { enabled: false },
        },
        additionalAcquisition: [
          {
            source: 'loki',
            url: 'http://loki.monitoring.svc.cluster.local:3100/',
            query: '{namespace="system",pod=~"traefik-.*"}',
            labels: { type: 'traefik' },
          },
        ],

        env: [
          {
            name: 'COLLECTIONS',
            value: 'crowdsecurity/traefik crowdsecurity/linux crowdsecurity/http-cve crowdsecurity/base-http-scenarios',
          },
          {
            name: 'PARSERS',
            value: 'crowdsecurity/geoip-enrich',
          },
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
    consoleEnrollmentSealedSecret: u.sealedSecret.forEnvNamed('crowdsec-console', {
      CROWDSEC_CONSOLE_ENROLLMENT_KEY: secrets.crowdsecConsoleEnrollmentKey,
    }),
    bouncerKeySealedSecret: u.sealedSecret.forEnvNamed('crowdsec-bouncer-key', {
      BOUNCER_KEY: secrets.bouncerKey,
    }),
    postgresPasswordSealedSecret: u.sealedSecret.wide.forEnvNamed('crowdsec-postgres-password', {
      USER_PASSWORD: postgresSecrets.userCrowdsec,
    }),
  },
}
