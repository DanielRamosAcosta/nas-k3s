local versions = import '../versions.json';
local amule = import 'arr/amule.libsonnet';
local deluge = import 'arr/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr.libsonnet';
local norznab = import 'arr/norznab.libsonnet';
local radarr = import 'arr/radarr.libsonnet';
local slskd = import 'arr/slskd.libsonnet';
local sonarr = import 'arr/sonarr.libsonnet';

{
  sonarr: sonarr.new(
    version=versions.sonarr.version,
  ),
  radarr: radarr.new(
    version=versions.radarr.version,
  ),
  lidarr: lidarr.new(
    version=versions.lidarr.version,
  ),
  slskd: slskd.new(
    version=versions.slskd.version,
  ),
  deluge: deluge.new(
    version=versions.deluge.version,
  ),
  jdownloader: jdownloader.new(
    version=versions.jdownloader.version,
  ),
  norznab: norznab.new(
    version='main-dc95fd6',
  ),
}
