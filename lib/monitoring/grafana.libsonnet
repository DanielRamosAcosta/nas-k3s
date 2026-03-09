local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

local lokiDatasource = importstr './grafana.datasource.loki.yml';
local prometheusDatasource = importstr './grafana.datasource.prometheus.yml';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='docker.io/grafana/grafana-oss', version):: {
    deployment: deployment.new('grafana', replicas=1, containers=[
                  container.new('grafana', u.image(image, version)) +
                  container.withPorts([containerPort.new('http', 3000)]) +
                  container.withEnv(
                    u.envVars.fromConfigMap(self.configEnv) +
                    u.envVars.fromSecret(self.secretEnv)
                  ) +
                  container.withVolumeMounts([
                    u.volumeMount.fromFile(self.lokiDatasource, '/usr/share/grafana/conf/provisioning/datasources'),
                    u.volumeMount.fromFile(self.prometheusDatasource, '/usr/share/grafana/conf/provisioning/datasources'),
                  ]),
                ]) +
                u.injectFiles([self.lokiDatasource, self.prometheusDatasource]),

    service: k.util.serviceFor(self.deployment),

    configEnv: u.configMap.forEnv(self.deployment, {
      GF_SERVER_ROOT_URL: 'https://grafana.danielramos.me',

      GF_DATABASE_TYPE: 'postgres',
      GF_DATABASE_HOST: 'postgres.databases.svc.cluster.local:5432',
      GF_DATABASE_NAME: 'grafana',
      GF_DATABASE_USER: 'grafana',

      GF_AUTH_DISABLE_LOGIN_FORM: 'true',

      GF_EXPLORE_ENABLED: 'true',

      GF_AUTH_GENERIC_OAUTH_ENABLED: 'true',
      GF_AUTH_GENERIC_OAUTH_NAME: 'Authelia',
      GF_AUTH_GENERIC_OAUTH_ICON: 'signin',
      GF_AUTH_GENERIC_OAUTH_SCOPES: 'openid profile email groups',
      GF_AUTH_GENERIC_OAUTH_EMPTY_SCOPES: 'false',
      GF_AUTH_GENERIC_OAUTH_AUTH_URL: 'https://auth.danielramos.me/api/oidc/authorization',
      GF_AUTH_GENERIC_OAUTH_TOKEN_URL: 'https://auth.danielramos.me/api/oidc/token',
      GF_AUTH_GENERIC_OAUTH_API_URL: 'https://auth.danielramos.me/api/oidc/userinfo',
      GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH: 'preferred_username',
      GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH: 'groups',
      GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH: 'name',
      GF_AUTH_GENERIC_OAUTH_USE_PKCE: 'true',
      GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH: "contains(groups[*], 'admins') && 'Admin' || contains(groups[*], 'editors') && 'Editor' || 'Viewer'",
      GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_STRICT: 'true',

      GF_PATHS_PROVISIONING: '/usr/share/grafana/conf/provisioning',

      GF_LOG_MODE: 'console',
      GF_LOG_CONSOLE_FORMAT: 'json',
    }),

    secretEnv: u.secret.forEnv(self.deployment, {
      GF_DATABASE_PASSWORD: s.POSTGRES_PASSWORD_GRAFANA,
      GF_AUTH_GENERIC_OAUTH_CLIENT_ID: s.AUTHELIA_OIDC_GRAFANA_CLIENT_ID,
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: s.AUTHELIA_OIDC_GRAFANA_CLIENT_SECRET,
    }),

    lokiDatasource: u.configMap.forFile('loki.yaml', lokiDatasource),
    prometheusDatasource: u.configMap.forFile('prometheus.yaml', prometheusDatasource),

    ingressRoute: u.ingressRoute.from(self.service, 'grafana.danielramos.me'),
  },
}
