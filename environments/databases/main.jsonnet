local couchdbExporter = import 'databases/couchdb/couchdb-exporter.libsonnet';
local couchdb = import 'databases/couchdb/couchdb.libsonnet';
local mariadb = import 'databases/mariadb/mariadb.libsonnet';
local mariadbExporter = import 'databases/mariadb/mariadb-exporter.libsonnet';
local postgres = import 'databases/postgres/postgres.libsonnet';
local valkeyExporter = import 'databases/valkey/valkey-exporter.libsonnet';
local valkey = import 'databases/valkey/valkey.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  postgres: postgres.new(),
  valkey: valkey.new(),
  valkeyExporter: valkeyExporter.new(),
  mariadb: mariadb.new(),
  mariadbExporter: mariadbExporter.new(),
  couchdb: couchdb.new(),
  couchdbExporter: couchdbExporter.new(),
})
