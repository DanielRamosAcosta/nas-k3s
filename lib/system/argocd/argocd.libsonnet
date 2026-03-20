local u = import '../../utils.libsonnet';
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local secrets = import 'system/argocd/argocd.secrets.json';

local helm = tanka.helm.new(std.thisFile);

{
  new(apps={}):: {
    local this = self,

    helm: helm.template('argocd', '../../../charts/argo-cd', {
      namespace: 'argocd',
      values: {
        dex: { enabled: false },
        redis: { enabled: false },
        redisSecretInit: { enabled: false },
        externalRedis: {
          host: 'valkey.databases.svc.cluster.local',
          port: 6379,
        },
        configs: {
          params: {
            'server.insecure': true,
          },
          cm: {
            url: 'https://argocd.danielramos.me',
            'admin.enabled': 'false',
            'oidc.config': std.manifestYamlDoc({
              name: 'Authelia',
              issuer: 'https://auth.danielramos.me',
              clientID: '$argocd-oidc-secret:client-id',
              clientSecret: '$argocd-oidc-secret:client-secret',
              cliClientID: '$argocd-oidc-secret:cli-client-id',
              requestedScopes: ['openid', 'email', 'groups', 'offline_access'],
              enableUserInfoGroups: true,
              userInfoPath: '/api/oidc/userinfo',
            }),
          },
          rbac: {
            'policy.csv': 'g, admins, role:admin',
            scopes: '[groups]',
          },
          secret: {
            createSecret: false,
          },
        },
      },
    }),

    argocd_secret: u.sealedSecret.forEnvNamed('argocd-secret', secrets.argocdSecret)
                   + u.labels.partOf('argocd')
                   + u.labels.templatePartOf('argocd'),

    oidc_sealed_secret: u.sealedSecret.forEnvNamed('argocd-oidc-secret', secrets.argocd)
                        + u.labels.partOf('argocd')
                        + u.labels.templatePartOf('argocd'),

    ingress_route: u.ingressRoute.from(this.helm.service_argocd_server, 'argocd.danielramos.me'),

  } + {
    // Applications — generated dynamically from apps map
    [u.argocd.appKey(name)]: u.argocd.app(name, name, apps[name])
    for name in std.objectFields(apps)
  },
}
