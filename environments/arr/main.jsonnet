local deluge = import 'arr/deluge.libsonnet';
local jdownloader = import 'arr/jdownloader.libsonnet';
local lidarr = import 'arr/lidarr.libsonnet';
local norznab = import 'arr/norznab.libsonnet';
local radarr = import 'arr/radarr.libsonnet';
local slskd = import 'arr/slskd.libsonnet';
local sonarr = import 'arr/sonarr.libsonnet';
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
