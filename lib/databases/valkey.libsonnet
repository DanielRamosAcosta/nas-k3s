local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local s = import 'secrets.json';
local u = import 'utils.libsonnet';

{
  local statefulSet = k.apps.v1.statefulSet,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new(image='valkey/valkey', version):: {
    statefulSet: statefulSet.new('valkey', replicas=1, containers=[
      container.new('valkey', u.image(image, version)) +
      container.withPorts(
        [containerPort.new('valkey', 6379)]
      ),
    ]),

    service: k.util.serviceFor(self.statefulSet),
  },
}
