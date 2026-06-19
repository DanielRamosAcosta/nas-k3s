local u = import 'utils.libsonnet';
local synapse = import 'communications/synapse/synapse.libsonnet';

u.Environment({
  synapse: synapse.new(),
})
