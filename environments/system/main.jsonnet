local cloudflare = import 'system/cloudflare/cloudflare.libsonnet';
local genericDevicePlugin = import 'system/generic-device-plugin/generic-device-plugin.libsonnet';
local gluetun = import 'system/gluetun/gluetun.libsonnet';
local reloader = import 'system/reloader/reloader.libsonnet';
local sealedSecrets = import 'system/sealed-secrets/sealed-secrets.libsonnet';
local smtpRelay = import 'system/smtp-relay/smtp-relay.libsonnet';
local traefik = import 'system/traefik/traefik.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  cloudflare: cloudflare.new(),
  'generic-device-plugin': genericDevicePlugin.new(),
  gluetun: gluetun.new(),
  reloader: reloader.new(),
  'sealed-secrets': sealedSecrets.new(),
  'smtp-relay': smtpRelay.new(),
  traefik: traefik.new(),
})
