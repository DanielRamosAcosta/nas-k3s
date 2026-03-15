local deluge = import 'arr/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr.libsonnet';
local norznab = import 'arr/norznab.libsonnet';
local radarr = import 'arr/radarr.libsonnet';
local slskd = import 'arr/slskd.libsonnet';
local sonarr = import 'arr/sonarr.libsonnet';

{
  sonarr: sonarr.new(),
  radarr: radarr.new(),
  lidarr: lidarr.new(),
  slskd: slskd.new(),
  deluge: deluge.new(),
  jdownloader: jdownloader.new(),
  norznab: norznab.new(),
}
