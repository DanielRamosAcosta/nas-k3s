local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local u = self,

  image(name, version):: name + ':' + version,
  secretRef(secretName, key):: k.core.v1.envVar.fromSecretRef(key, secretName, key),
  extractConfig(configMapName, keys):: [
    k.core.v1.envVar.withName(key) +
    k.core.v1.envVar.valueFrom.configMapKeyRef.withKey(key) +
    k.core.v1.envVar.valueFrom.configMapKeyRef.withName(configMapName)
    for key in keys
  ],
  extractSecrets(secretName, keys):: [
    self.secretRef(secretName, key)
    for key in keys
  ],
  base64Keys(object):: {
    [key]: std.base64(object[key])
    for key in std.objectFields(object)
  },
  jsonStringify(object):: std.manifestJsonEx(object, '  '),
  utils: {
    join(elements, separator=','):: std.join(separator, elements),
  },
  joinedEnv(name, elements):: [
    k.core.v1.envVar.new(name, std.join(',', elements)),
  ],
  keysFromSecret(secret):: std.objectFieldsAll(secret.data),
  fromFile(configMapOrSecret, path):: k.core.v1.volumeMount.new(configMapOrSecret.metadata.name, path + '/' + std.objectFieldsAll(configMapOrSecret.data)[0]) + k.core.v1.volumeMount.withSubPath(std.objectFieldsAll(configMapOrSecret.data)[0]),
  injectFiles(configMapOrSecrets):: k.apps.v1.deployment.spec.template.spec.withVolumes([
    if resource.kind == 'Secret' then
      k.core.v1.volume.fromSecret(resource.metadata.name, resource.metadata.name)
    else
      k.core.v1.volume.fromConfigMap(resource.metadata.name, resource.metadata.name)
    for resource in configMapOrSecrets
  ]),
  injectFile(resource)::
    if resource.kind == 'Secret' then
      k.core.v1.volume.fromSecret(resource.metadata.name, resource.metadata.name)
    else
      k.core.v1.volume.fromConfigMap(resource.metadata.name, resource.metadata.name)
  ,
  withoutSchema(object):: std.prune(std.mergePatch(object, { '$schema': null })),
  normalizeName(name):: std.strReplace(std.strReplace(name, '.', '-'), '_', '-'),
  pv: {
    localPathFor(component, storage, path):: u.pv.atLocal(component.metadata.name + '-pv', storage, path),
    atLocal(name, storage, path):: {
      apiVersion: 'v1',
      kind: 'PersistentVolume',
      metadata: {
        name: name,
      },
      spec: {
        capacity: {
          storage: storage,
        },
        accessModes: [
          'ReadWriteOnce',
        ],
        storageClassName: 'local-path',
        persistentVolumeReclaimPolicy: 'Retain',
        hostPath: {
          path: path,
          type: 'DirectoryOrCreate',
        },
      },
    },
  },
  pvc: {
    from(pv):: u.pvc.atLocal(pv.metadata.name + 'c', pv.metadata.name, pv.spec.capacity.storage),
    atLocal(name, pv, storage):: {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: name,
      },
      spec: {
        accessModes: [
          'ReadWriteOnce',
        ],
        storageClassName: 'local-path',
        resources: {
          requests: {
            storage: storage,
          },
        },
        volumeName: pv,
      },
    },
  },
  volumeMount: {
    fromFile(configMapOrSecret, path):: k.core.v1.volumeMount.new(configMapOrSecret.metadata.name, path + '/' + std.objectFieldsAll(configMapOrSecret.data)[0]) + k.core.v1.volumeMount.withSubPath(std.objectFieldsAll(configMapOrSecret.data)[0]),
  },
  volume: {
    fromConfigMap(configMap):: k.core.v1.volume.fromConfigMap(configMap.metadata.name, configMap.metadata.name),
    fromSecret(secret):: k.core.v1.volume.fromSecret(secret.metadata.name, secret.metadata.name),
    fromHostPath(name, path):: k.core.v1.volume.fromHostPath(name, path),
  },
  secret: {
    forFile(fileName, content):: k.core.v1.secret.new(u.normalizeName(fileName), {
      [fileName]: std.base64(content),
    }),
    forEnv(component, content):: k.core.v1.secret.new(component.metadata.name + '-secret-env', u.base64Keys(content)),
  },
  configMap: {
    forFile(fileName, content):: k.core.v1.configMap.new(u.normalizeName(fileName), {
      [fileName]: content,
    }),
    forEnv(component, content):: k.core.v1.configMap.new(component.metadata.name + '-config-env', content),
  },
  envVars: {
    fromConfigMap(configMap):: u.extractConfig(configMap.metadata.name, std.objectFieldsAll(configMap.data)),
    fromSecret(secret):: u.extractSecrets(secret.metadata.name, u.keysFromSecret(secret)),
  },
  ingressRoute: {
    from(service, hostOrMap, middlewares=[])::
      if std.type(hostOrMap) == 'string' then
        self.fromDefaultPort(service, hostOrMap, middlewares)
      else
        self.fromPortToHostMap(service, hostOrMap),
    fromDefaultPort(service, host, middlewares):: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'IngressRoute',
      metadata: {
        name: service.metadata.name + '-ingressroute',
      },
      spec: {
        entryPoints: [
          'websecure',
        ],
        routes: [
          {
            match: 'Host(`' + host + '`)',
            kind: 'Rule',
            services: [
              {
                name: service.metadata.name,
                port: service.spec.ports[0].port,
              },
            ],
            middlewares: if std.length(middlewares) > 0 then middlewares else null,
          },
        ],
        tls: {
          certResolver: 'le',
        },
      },
    },
    fromPortToHostMap(service, portToHostMap):: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'IngressRoute',
      metadata: {
        name: service.metadata.name + '-ingressroute',
      },
      spec: {
        entryPoints: [
          'websecure',
        ],
        routes: [
          {
            match: 'Host(`' + portToHostMap[port] + '`)',
            kind: 'Rule',
            services: [
              {
                name: service.metadata.name,
                port: std.parseInt(port),
              },
            ],
          }
          for port in std.objectFields(portToHostMap)
        ],
        tls: {
          certResolver: 'le',
        },
      },
    },
  },
  command: {
    jq: {
      merge(firstFilePath, secondFilePath, output):: k.core.v1.container.withCommand([
        'sh',
        '-c',
        "jq -s '.[0] * .[1]' " + firstFilePath + ' ' + secondFilePath + ' > ' + output,
      ]),
    },
  },
  rbac(name, namespace, rules):: {
    local clusterRole = k.rbac.v1.clusterRole,
    local clusterRoleBinding = k.rbac.v1.clusterRoleBinding,
    local subject = k.rbac.v1.subject,
    local serviceAccount = k.core.v1.serviceAccount,

    service_account:
      serviceAccount.new(name),

    cluster_role:
      clusterRole.new() +
      clusterRole.mixin.metadata.withName(name) +
      clusterRole.withRules(rules),

    cluster_role_binding:
      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName(name) +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withKind('ClusterRole') +
      clusterRoleBinding.mixin.roleRef.withName(name) +
      clusterRoleBinding.withSubjects([
        subject.new() +
        subject.withKind('ServiceAccount') +
        subject.withName(name) +
        subject.withNamespace(namespace),
      ]),
  },
  prometheus(port, path='/metrics')::
    k.core.v1.service.metadata.withAnnotations({
      'prometheus.io/path': path,
      'prometheus.io/scrape': 'true',
      'prometheus.io/port': port,
    }),
  traefik: {
    middleware: {
      new(name, namespace):: {
        apiVersion: 'traefik.io/v1alpha1',
        kind: 'Middleware',
        metadata: {
          name: name,
          namespace: namespace,
        },
      },
      spec: {
        withforwardAuth(address, authResponseHeaders):: {
          spec+: {
            forwardAuth: {
              address: address,
              authResponseHeaders: authResponseHeaders,
            },
          },
        },
      },
    },
  },
}
