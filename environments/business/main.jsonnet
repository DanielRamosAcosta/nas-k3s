local facturascripts = import 'business/facturascripts/facturascripts.libsonnet';
local u = import 'utils.libsonnet';
local wger = import 'business/wger/wger.libsonnet';

u.Environment({
  facturascripts: facturascripts.new(),
  wger: wger.new(),
})
