local facturascripts = import 'business/facturascripts/facturascripts.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  facturascripts: facturascripts.new(),
})
