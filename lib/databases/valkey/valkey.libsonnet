local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('valkey', replicas=1, containers=[
      container.new('valkey', u.image(versions.valkey.image, versions.valkey.version)) +
      container.withPorts(
        [containerPort.new('valkey', 6379)]
      ) +
      u.probes.stateful.tcp(6379),
    ]),

    service: k.util.serviceFor(self.deployment),
  },
}
