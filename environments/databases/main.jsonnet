local versions = import '../versions.json';
local mariadb = import 'databases/mariadb.libsonnet';
local postgres = import 'databases/postgres.libsonnet';
local valkey = import 'databases/valkey.libsonnet';

{
  postgres: postgres.new(
    image=versions.postgres.image,
    version=versions.postgres.version,
  ),
  valkey: valkey.new(
    image=versions.valkey.image,
    version=versions.valkey.version,
  ),
  mariadb: mariadb.new(
    image=versions.mariadb.image,
    version=versions.mariadb.version,
  ),
}
