local versions = import '../versions.json';
local cloudflare = import 'system/cloudflare.libsonnet';
local gluetun = import 'system/gluetun.libsonnet';
local heartbeat = import 'system/heartbeat.libsonnet';

{
  cloudflare: cloudflare.new(
    image=versions.cloudflare.image,
    version=versions.cloudflare.version,
  ),
  gluetun: gluetun.new(
    image=versions.gluetun.image,
    version=versions.gluetun.version,
  ),
  heartbeat: heartbeat.new(
    image=versions.heartbeat.image,
    version=versions.heartbeat.version,
  ),
}
