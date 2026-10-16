local couchdbExporter = import 'databases/couchdb/couchdb-exporter.libsonnet';
local couchdb = import 'databases/couchdb/couchdb.libsonnet';
local mariadb = import 'databases/mariadb/mariadb.libsonnet';
local postgres = import 'databases/postgres/postgres.libsonnet';
local valkeyExporter = import 'databases/valkey/valkey-exporter.libsonnet';
local valkey = import 'databases/valkey/valkey.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  postgres: postgres.new(),
  valkey: valkey.new(),
  valkeyExporter: valkeyExporter.new(),
  mariadb: mariadb.new(),
  couchdb: couchdb.new(),
  couchdbExporter: couchdbExporter.new(),
})
