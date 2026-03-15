local cloudflare = import 'system/cloudflare.libsonnet';
local gluetun = import 'system/gluetun.libsonnet';
local heartbeat = import 'system/heartbeat.libsonnet';

{
  cloudflare: cloudflare.new(),
  gluetun: gluetun.new(),
  heartbeat: heartbeat.new(),
}
