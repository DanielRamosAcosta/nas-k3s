local cloudflare = import 'system/cloudflare/cloudflare.libsonnet';
local gluetun = import 'system/gluetun/gluetun.libsonnet';
local sealedSecrets = import 'system/sealed-secrets/sealed-secrets.libsonnet';
local u = import 'utils.libsonnet';

{
  cloudflare: u.labelApp('cloudflare', cloudflare.new()),
  gluetun: u.labelApp('gluetun', gluetun.new()),
  sealed_secrets: u.labelApp('sealed-secrets', sealedSecrets.new()),
}
