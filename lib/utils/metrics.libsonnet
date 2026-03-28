local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  annotations(port, path='/metrics')::
    k.core.v1.service.metadata.withAnnotations({
      'prometheus.io/path': path,
      'prometheus.io/scrape': 'true',
      'prometheus.io/port': port,
    }),
}
