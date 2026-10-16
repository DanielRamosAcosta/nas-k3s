local u = import '../../utils.libsonnet';
local versions = import '../../versions.json';
local k = import 'github.com/grafana/jsonnet-libs/ksonnet-util/kausal.libsonnet';

{
  local deployment = k.apps.v1.deployment,
  local container = k.core.v1.container,
  local containerPort = k.core.v1.containerPort,
  local envVar = k.core.v1.envVar,

  // /_node/_stats requiere server admin; CouchDB no ofrece un rol readonly granular,
  // así que se reusa el admin principal ya sellado (couchdb-sealed-secret). Read-only de
  // facto: el exporter solo hace GETs de stats. El gesellix exporter espera las env
  // COUCHDB_USERNAME/COUCHDB_PASSWORD, pero la key del Secret es COUCHDB_USER → se mapea
  // a mano (fromSecretRef no sirve vía fromSealedSecret, que usa la key literal).
  local couchdbSecretName = 'couchdb-sealed-secret',

  new():: {
    deployment: deployment.new('couchdb-exporter', replicas=1, containers=[
      container.new('couchdb-exporter', u.image(versions.couchdbExporter.image, versions.couchdbExporter.version)) +
      container.withPorts(containerPort.new('metrics', 9984)) +
      container.withEnv(
        u.envVars.fromConfigMap(self.configEnv) + [
          envVar.fromSecretRef('COUCHDB_USERNAME', couchdbSecretName, 'COUCHDB_USER'),
          envVar.fromSecretRef('COUCHDB_PASSWORD', couchdbSecretName, 'COUCHDB_PASSWORD'),
        ],
      ) +
      u.probes.http('/metrics', 9984),
    ]),

    service: k.util.serviceFor(self.deployment) + u.metrics('9984'),

    configEnv: u.configMap.forEnv(self.deployment, {
      COUCHDB_URI: 'http://couchdb.databases.svc.cluster.local:5984',
      // Por defecto escucha en localhost:9984 → inalcanzable desde el Service. Bind a todas
      // las interfaces para que el scrape por anotación llegue al pod.
      TELEMETRY_ADDRESS: ':9984',
    }),
  },
}
