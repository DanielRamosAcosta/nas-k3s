local deluge = import 'arr/deluge/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr/lidarr.libsonnet';
local norznab = import 'arr/norznab/norznab.libsonnet';
local radarr = import 'arr/radarr/radarr.libsonnet';
local slskd = import 'arr/slskd/slskd.libsonnet';
local sonarr = import 'arr/sonarr/sonarr.libsonnet';
local u = import 'utils.libsonnet';

{
  sonarr: u.labelApp('sonarr', sonarr.new()),
  radarr: u.labelApp('radarr', radarr.new()),
  lidarr: u.labelApp('lidarr', lidarr.new()),
  slskd: u.labelApp('slskd', slskd.new()),
  deluge: u.labelApp('deluge', deluge.new()),
  jdownloader: u.labelApp('jdownloader', jdownloader.new()),
  norznab: u.labelApp('norznab', norznab.new()),
}
