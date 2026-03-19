local authelia = import 'auth/authelia/authelia.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  authelia: authelia.new(),
})
