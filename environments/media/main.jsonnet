local beets = import 'media/beets.libsonnet';
local booklore = import 'media/booklore.libsonnet';
local gitea = import 'media/gitea.libsonnet';
local immich = import 'media/immich.libsonnet';
local invidious = import 'media/invidious.libsonnet';
local jellyfin = import 'media/jellyfin.libsonnet';
local navidrome = import 'media/navidrome.libsonnet';
local sftpgo = import 'media/sftpgo.libsonnet';
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
