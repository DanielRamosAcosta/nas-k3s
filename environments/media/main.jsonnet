local beets = import 'media/beets.libsonnet';
local booklore = import 'media/booklore.libsonnet';
local gitea = import 'media/gitea.libsonnet';
local immich = import 'media/immich.libsonnet';
local invidious = import 'media/invidious.libsonnet';
local jellyfin = import 'media/jellyfin.libsonnet';
local navidrome = import 'media/navidrome.libsonnet';
local sftpgo = import 'media/sftpgo.libsonnet';

{
  beets: beets.new(),
  immich: immich.new(),
  navidrome: navidrome.new(),
  sftpgo: sftpgo.new(),
  gitea: gitea.new(),
  booklore: booklore.new(),
  jellyfin: jellyfin.new(),
  invidious: invidious.new(),
}
