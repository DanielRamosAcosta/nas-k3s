local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,

  new():: {
    deployment: deployment.new('mc-monitor', replicas=1, containers=[
      container.new('mc-monitor', u.image(versions.mcMonitor.image, versions.mcMonitor.version)) +
      container.withArgs([
        'export-for-prometheus',
        '--servers=minecraft.games.svc.cluster.local:25565',
      ]) +
      container.withPorts(containerPort.new('metrics', 8080)) +
      u.probes.http('/metrics', 8080),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('8080'),
  },
}
