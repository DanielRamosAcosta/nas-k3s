local versions = import '../versions.json';
local cloudflare = import 'system/cloudflare.libsonnet';
local gluetun = import 'system/gluetun.libsonnet';
local heartbeat = import 'system/heartbeat.libsonnet';

{
  cloudflare: cloudflare.new(
    version=versions.cloudflare.version
  ),
  gluetun: gluetun.new(
    version=versions.gluetun.version
  ),
  heartbeat: heartbeat.new(),
}
