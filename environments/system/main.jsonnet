local cloudflare = import 'system/cloudflare.libsonnet';
local gluetun = import 'system/gluetun.libsonnet';
local heartbeat = import 'system/heartbeat.libsonnet';
local sealedSecrets = import 'system/sealed-secrets.libsonnet';

{
  cloudflare: cloudflare.new(),
  gluetun: gluetun.new(),
  heartbeat: heartbeat.new(),
  sealed_secrets: sealedSecrets.new(),
}
