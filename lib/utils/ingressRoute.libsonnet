{
  tlsStore(sealedSecret):: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'TLSStore',
    metadata: {
      name: 'default',
    },
    spec: {
      defaultCertificate: {
        secretName: sealedSecret.metadata.name,
      },
    },
  },
  tlsStoreGenerated(resolver, mainDomain, sans=[]):: {
    apiVersion: 'traefik.io/v1alpha1',
    kind: 'TLSStore',
    metadata: {
      name: 'default',
    },
    spec: {
      defaultGeneratedCert: {
        resolver: resolver,
        domain: {
          main: mainDomain,
          sans: sans,
        },
      },
    },
  },
  from(service, hostOrMap, middlewares=[], extraRoutes=[])::
    if std.type(hostOrMap) == 'string' then
      self.fromDefaultPort(service, hostOrMap, middlewares, extraRoutes)
    else
      self.fromPortToHostMap(service, hostOrMap),
  fromDefaultPort(service, host, middlewares, extraRoutes=[]):: {
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
          [if std.length(middlewares) > 0 then 'middlewares']: middlewares,
        },
      ] + extraRoutes,
      tls: { store: { name: 'default' } },
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
        store: { name: 'default' },
      },
    },
  },
}
