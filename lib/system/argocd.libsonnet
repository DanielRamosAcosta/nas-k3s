local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local secrets = import 'system/argocd.secrets.json';
local u = import 'utils.libsonnet';

local helm = tanka.helm.new(std.thisFile);

local makeApp(name, path, namespace) = {
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: name,
    namespace: 'argocd',
  },
  spec: {
    project: 'default',
    source: {
      repoURL: 'https://github.com/DanielRamosAcosta/nas-k3s.git',
      targetRevision: 'manifests',
      path: path,
    },
    destination: {
      server: 'https://kubernetes.default.svc',
      namespace: namespace,
    },
    syncPolicy: {
      automated: {
        prune: true,
        selfHeal: true,
      },
    },
  },
};

{
  new(apps={}):: {
    local this = self,

    helm: helm.template('argocd', '../../charts/argo-cd', {
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
              requestedScopes: ['openid', 'email', 'groups'],
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

    argocd_secret: u.sealedSecret.forEnvNamed('argocd-secret', secrets.argocdSecret) {
      metadata+: {
        labels+: {
          'app.kubernetes.io/part-of': 'argocd',
        },
      },
      spec+: {
        template+: {
          metadata+: {
            labels+: {
              'app.kubernetes.io/part-of': 'argocd',
            },
          },
        },
      },
    },

    oidc_sealed_secret: u.sealedSecret.forEnvNamed('argocd-oidc-secret', secrets.argocd) {
      spec+: {
        template+: {
          metadata+: {
            labels+: {
              'app.kubernetes.io/part-of': 'argocd',
            },
          },
        },
      },
    },

    ingress_route: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'IngressRoute',
      metadata: {
        name: 'argocd-server-ingressroute',
        namespace: 'argocd',
      },
      spec: {
        entryPoints: ['websecure'],
        routes: [{
          match: 'Host(`argocd.danielramos.me`)',
          kind: 'Rule',
          services: [{
            name: 'argocd-server',
            port: 80,
          }],
        }],
        tls: {
          certResolver: 'le',
        },
      },
    },

  } + {
    // Applications — generated dynamically from apps map
    ['app_' + std.strReplace(name, '-', '_')]: makeApp(name, name, apps[name])
    for name in std.objectFields(apps)
    if name != 'argocd'
  } + {
    // argocd manages itself with ServerSideApply (applicationsets CRD > 262KB)
    app_argocd: makeApp('argocd', 'argocd', 'argocd') {
      spec+: {
        syncPolicy: {
          syncOptions: ['ServerSideApply=true'],
        },
      },
    },
  },
}
