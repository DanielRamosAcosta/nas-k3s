local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('redis-exporter', replicas=1, containers=[
      container.new('redis-exporter', u.image(versions.redisExporter.image, versions.redisExporter.version)) +
      container.withPorts(containerPort.new('metrics', 9121)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv),
      ) +
      u.probes.http('/', 9121),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('9121'),

    configEnv: u.configMap.forEnv(self.deployment, {
      REDIS_ADDR: 'redis://valkey.databases.svc.cluster.local:6379',
    }),
  },
}
