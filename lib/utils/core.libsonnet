{
  image(name, version):: name + ':' + version,

  local reloaderKinds = std.set(['DaemonSet', 'Deployment', 'StatefulSet']),

  labelApp(appName, resources)::
    local recurse(appName, res) = {
      [key]:
        local val = res[key];
        if std.isObject(val) && std.objectHas(val, 'metadata') then
          val { metadata+: { labels+: { app: appName } } }
          + (
            if std.objectHas(val, 'kind') && std.setMember(val.kind, reloaderKinds) then
              { spec+: { template+: { metadata+: { annotations+: {
                'reloader.stakater.com/auto': 'true',
              } } } } }
            else
              {}
          )
        else if std.isObject(val) then
          recurse(appName, val)
        else
          val
      for key in std.objectFields(res)
    };
    recurse(appName, resources),

  normalizeName(name):: std.strReplace(std.strReplace(name, '.', '-'), '_', '-'),

  withoutSchema(object):: std.prune(std.mergePatch(object, { '$schema': null })),
}
