local mariadb = import 'databases/mariadb/mariadb.libsonnet';
local postgres = import 'databases/postgres/postgres.libsonnet';
local valkey = import 'databases/valkey/valkey.libsonnet';
local u = import 'utils.libsonnet';

{
  postgres: u.labelApp('postgres', postgres.new()),
  valkey: u.labelApp('valkey', valkey.new()),
  mariadb: u.labelApp('mariadb', mariadb.new()),
}
