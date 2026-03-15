local authelia = import 'auth/authelia.libsonnet';
local satph = import 'auth/satph.libsonnet';
local u = import 'utils.libsonnet';

{
  authelia: u.labelApp('authelia', authelia.new()),
  satph: u.labelApp('satph', satph.new()),
}
