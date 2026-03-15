local versions = import '../versions.json';
local deluge = import 'arr/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr.libsonnet';
local norznab = import 'arr/norznab.libsonnet';
local radarr = import 'arr/radarr.libsonnet';
local slskd = import 'arr/slskd.libsonnet';
local sonarr = import 'arr/sonarr.libsonnet';

{
  sonarr: sonarr.new(
    image=versions.sonarr.image,
    version=versions.sonarr.version,
  ),
  radarr: radarr.new(
    image=versions.radarr.image,
    version=versions.radarr.version,
  ),
  lidarr: lidarr.new(
    image=versions.lidarr.image,
    version=versions.lidarr.version,
  ),
  slskd: slskd.new(
    image=versions.slskd.image,
    version=versions.slskd.version,
  ),
  deluge: deluge.new(
    image=versions.deluge.image,
    version=versions.deluge.version,
  ),
  jdownloader: jdownloader.new(
    image=versions.jdownloader.image,
    version=versions.jdownloader.version,
  ),
  norznab: norznab.new(
    image=versions.norznab.image,
    version=versions.norznab.version,
  ),
}
