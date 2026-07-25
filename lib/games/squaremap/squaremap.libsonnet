local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

local nginxConfContent = importstr './squaremap.nginx.conf';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local volume = k.core.v1.volume,
  local volumeMount = k.core.v1.volumeMount,

  new():: {
    local this = self,

    deployment: deployment.new('squaremap', replicas=1, containers=[
                  container.new('nginx', u.image(versions.nginx.image, versions.nginx.version)) +
                  container.withPorts([containerPort.new('http', 80)]) +
                  container.withVolumeMounts([
                    volumeMount.new('web', '/usr/share/nginx/html', true),
                    volumeMount.new(this.nginxConfig.metadata.name, '/etc/nginx/conf.d/default.conf') + volumeMount.withSubPath('default.conf') + volumeMount.withReadOnly(true),
                  ]) +
                  u.probes.http('/', 80),
                ]) +
                deployment.spec.template.spec.withVolumes([
                  volume.fromHostPath('web', '/data/minecraft/plugins/squaremap/web'),
                  { name: this.nginxConfig.metadata.name, configMap: { name: this.nginxConfig.metadata.name } },
                ]),

    service: k.util.serviceFor(self.deployment),

    ingressRoute: u.ingressRoute.from(self.service, 'mcmap.danielramos.me'),

    nginxConfig: u.configMap.forFile('default.conf', nginxConfContent) + { metadata+: { name: 'squaremap-nginx-conf' } },
  },
}
