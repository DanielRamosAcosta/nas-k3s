local beets = import 'media/beets/beets.libsonnet';
local booklore = import 'media/booklore/booklore.libsonnet';
local immich = import 'media/immich/immich.libsonnet';
local invidious = import 'media/invidious/invidious.libsonnet';
local jellyfin = import 'media/jellyfin/jellyfin.libsonnet';
local navidrome = import 'media/navidrome/navidrome.libsonnet';
local sftpgo = import 'media/sftpgo/sftpgo.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  beets: beets.new(),
  immich: immich.new(),
  navidrome: navidrome.new(),
  sftpgo: sftpgo.new(),
  booklore: booklore.new(),
  jellyfin: jellyfin.new(),
  invidious: invidious.new(),
})
