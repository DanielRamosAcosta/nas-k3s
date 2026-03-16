local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';
local core = import 'utils/core.libsonnet';

{
  forFile(fileName, content):: k.core.v1.configMap.new(core.normalizeName(fileName), {
    [fileName]: content,
  }),
  forEnv(component, content):: k.core.v1.configMap.new(component.metadata.name + '-config-env', content),
}
