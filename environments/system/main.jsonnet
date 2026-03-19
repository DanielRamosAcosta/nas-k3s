local cloudflare = import 'system/cloudflare/cloudflare.libsonnet';
local gluetun = import 'system/gluetun/gluetun.libsonnet';
local sealedSecrets = import 'system/sealed-secrets/sealed-secrets.libsonnet';
local traefik = import 'system/traefik/traefik.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  cloudflare: cloudflare.new(),
  gluetun: gluetun.new(),
  'sealed-secrets': sealedSecrets.new(),
  traefik: traefik.new(),
})
