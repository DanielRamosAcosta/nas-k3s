local mariadb = import 'databases/mariadb.libsonnet';
local postgres = import 'databases/postgres.libsonnet';
local valkey = import 'databases/valkey.libsonnet';
local u = import 'utils.libsonnet';

{
  postgres: u.labelApp('postgres', postgres.new()),
  valkey: u.labelApp('valkey', valkey.new()),
  mariadb: u.labelApp('mariadb', mariadb.new()),
}
