local authelia = import 'auth/authelia.libsonnet';
local u = import 'utils.libsonnet';

{
  authelia: u.labelApp('authelia', authelia.new()),
}
