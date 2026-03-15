local authelia = import 'auth/authelia.libsonnet';
local satph = import 'auth/satph.libsonnet';

{
  authelia: authelia.new(),
  satph: satph.new(),
}
