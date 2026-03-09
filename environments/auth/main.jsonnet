local versions = import '../versions.json';
local authelia = import 'auth/authelia.libsonnet';
local satph = import 'auth/satph.libsonnet';

{
  authelia: authelia.new(
    version=versions.authelia.version
  ),
  satph: satph.new(
    version='main-d35382b'
  ),
}
