local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  jq: {
    merge(firstFilePath, secondFilePath, output):: k.core.v1.container.withCommand([
      'sh',
      '-c',
      "jq -s '.[0] * .[1]' " + firstFilePath + ' ' + secondFilePath + ' > ' + output,
    ]),
  },
}
