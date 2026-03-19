local deluge = import 'arr/deluge/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr/lidarr.libsonnet';
local norznab = import 'arr/norznab/norznab.libsonnet';
local radarr = import 'arr/radarr/radarr.libsonnet';
local slskd = import 'arr/slskd/slskd.libsonnet';
local sonarr = import 'arr/sonarr/sonarr.libsonnet';
local u = import 'utils.libsonnet';

u.Environment({
  sonarr: sonarr.new(),
  radarr: radarr.new(),
  lidarr: lidarr.new(),
  slskd: slskd.new(),
  deluge: deluge.new(),
  jdownloader: jdownloader.new(),
  norznab: norznab.new(),
})
