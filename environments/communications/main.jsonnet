local synapse = import 'communications/synapse/synapse.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  synapse: synapse.new(),
})
