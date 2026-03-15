local cloudflare = import 'system/cloudflare.libsonnet';
local gluetun = import 'system/gluetun.libsonnet';
local heartbeat = import 'system/heartbeat.libsonnet';
local sealedSecrets = import 'system/sealed-secrets.libsonnet';
local u = import 'utils.libsonnet';

{
  cloudflare: u.labelApp('cloudflare', cloudflare.new()),
  gluetun: u.labelApp('gluetun', gluetun.new()),
  heartbeat: u.labelApp('heartbeat', heartbeat.new()),
  sealed_secrets: u.labelApp('sealed-secrets', sealedSecrets.new()),
}
