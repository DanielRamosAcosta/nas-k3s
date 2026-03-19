{
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
        store: { name: 'default' },
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
        store: { name: 'default' },
      },
    },
  },
}
