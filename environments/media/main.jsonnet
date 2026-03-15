local versions = import '../versions.json';
local beets = import 'media/beets.libsonnet';
local booklore = import 'media/booklore.libsonnet';
local gitea = import 'media/gitea.libsonnet';
local immich = import 'media/immich.libsonnet';
local invidious = import 'media/invidious.libsonnet';
local jellyfin = import 'media/jellyfin.libsonnet';
local navidrome = import 'media/navidrome.libsonnet';
local sftpgo = import 'media/sftpgo.libsonnet';

{
  beets: beets.new(
    image=versions.beets.image,
    version=versions.beets.version,
  ),
  immich: immich.new(
    image=versions.immich.image,
    version=versions.immich.version,
    mlImage=versions.immichMl.image,
  ),
  navidrome: navidrome.new(
    image=versions.navidrome.image,
    version=versions.navidrome.version,
  ),
  sftpgo: sftpgo.new(
    image=versions.sftpgo.image,
    version=versions.sftpgo.version,
  ),
  gitea: gitea.new(
    image=versions.gitea.image,
    version=versions.gitea.version,
  ),
  booklore: booklore.new(
    image=versions.booklore.image,
    version=versions.booklore.version,
  ),
  jellyfin: jellyfin.new(
    image=versions.jellyfin.image,
    version=versions.jellyfin.version,
  ),
  invidious: invidious.new(
    invidiousImage=versions.invidious.image,
    invidiousVersion=versions.invidious.version,
    invidiousCompanionImage=versions.invidiousCompanion.image,
    invidiousCompanionVersion=versions.invidiousCompanion.version,
  ),
}
