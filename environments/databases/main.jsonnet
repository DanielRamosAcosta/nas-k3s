local mariadb = import 'databases/mariadb/mariadb.libsonnet';
local postgres = import 'databases/postgres/postgres.libsonnet';
local valkey = import 'databases/valkey/valkey.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  postgres: postgres.new(),
  valkey: valkey.new(),
  mariadb: mariadb.new(),
})
