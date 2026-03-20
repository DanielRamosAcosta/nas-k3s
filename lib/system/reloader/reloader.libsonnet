local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

local helm = tanka.helm.new(std.thisFile);

{
  new():: helm.template('reloader', '../../../charts/reloader', {
    namespace: 'kube-system',
    values: {
      reloader: {
        watchGlobally: true,
      },
    },
  }),
}
