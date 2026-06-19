local synapse = import 'communications/synapse/synapse.libsonnet';
local mautrixWhatsapp = import 'communications/mautrix-whatsapp/mautrix-whatsapp.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  synapse: synapse.new(),
  mautrixWhatsapp: mautrixWhatsapp.new(),
})
