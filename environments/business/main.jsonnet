local facturascripts = import 'business/facturascripts/facturascripts.libsonnet';
local wger = import 'business/wger/wger.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  facturascripts: facturascripts.new(),
  wger: wger.new(),
})
