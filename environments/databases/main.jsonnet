local mariadb = import 'databases/mariadb.libsonnet';
local postgres = import 'databases/postgres.libsonnet';
local valkey = import 'databases/valkey.libsonnet';

{
  postgres: postgres.new(),
  valkey: valkey.new(),
  mariadb: mariadb.new(),
}
