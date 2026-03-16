local beets = import 'media/beets/beets.libsonnet';
local booklore = import 'media/booklore/booklore.libsonnet';
local gitea = import 'media/gitea/gitea.libsonnet';
local immich = import 'media/immich/immich.libsonnet';
local invidious = import 'media/invidious/invidious.libsonnet';
local jellyfin = import 'media/jellyfin/jellyfin.libsonnet';
local navidrome = import 'media/navidrome/navidrome.libsonnet';
local sftpgo = import 'media/sftpgo/sftpgo.libsonnet';
local u = import 'utils.libsonnet';

{
  beets: u.labelApp('beets', beets.new()),
  immich: u.labelApp('immich', immich.new()),
  navidrome: u.labelApp('navidrome', navidrome.new()),
  sftpgo: u.labelApp('sftpgo', sftpgo.new()),
  gitea: u.labelApp('gitea', gitea.new()),
  booklore: u.labelApp('booklore', booklore.new()),
  jellyfin: u.labelApp('jellyfin', jellyfin.new()),
  invidious: u.labelApp('invidious', invidious.new()),
}
