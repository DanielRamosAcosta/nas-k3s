local versions = import '../versions.json';
local authelia = import 'auth/authelia.libsonnet';
local satph = import 'auth/satph.libsonnet';

{
  authelia: authelia.new(
    image=versions.authelia.image,
    version=versions.authelia.version,
  ),
  satph: satph.new(
    image=versions.satph.image,
    version=versions.satph.version,
  ),
}
