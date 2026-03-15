local tanka = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';

local helm = tanka.helm.new(std.thisFile);

{
  new():: helm.template('sealed-secrets', '../../charts/sealed-secrets', {
    namespace: 'kube-system',
  }),
}
