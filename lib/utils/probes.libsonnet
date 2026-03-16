local k = import '../k.libsonnet';
local container = k.core.v1.container;

// Timing presets
local readinessTiming = {
  initialDelaySeconds: 5,
  periodSeconds: 10,
  timeoutSeconds: 5,
  failureThreshold: 3,
};

local livenessTiming = {
  initialDelaySeconds: 15,
  periodSeconds: 30,
  timeoutSeconds: 5,
  failureThreshold: 3,
};

local startupTiming = {
  periodSeconds: 10,
  timeoutSeconds: 5,
  failureThreshold: 30,
};

// Action builders
local httpAction(path, port) = {
  httpGet: { path: path, port: port, scheme: 'HTTP' },
};

local tcpAction(port) = {
  tcpSocket: { port: port },
};

local execAction(cmd) = {
  exec: { command: if std.isArray(cmd) then cmd else [cmd] },
};

// Probe composers
local readiness(action) = { readinessProbe: action + readinessTiming };
local liveness(action) = { livenessProbe: action + livenessTiming };
local startup(action) = { startupProbe: action + startupTiming };

// Preset: readiness + liveness (default, stateless services)
local standard(action) = readiness(action) + liveness(action);

// Preset: readiness + liveness + startup (slow-starting apps)
local withStartupPreset(action) = readiness(action) + liveness(action) + startup(action);

// Preset: readiness + startup, NO liveness (databases/stateful)
local statefulPreset(action) = readiness(action) + startup(action);

{
  // u.probes.http('/path', port) — readiness + liveness
  http(path, port):: standard(httpAction(path, port)),
  tcp(port):: standard(tcpAction(port)),
  exec(cmd):: standard(execAction(cmd)),

  // u.probes.withStartup.http('/path', port) — readiness + liveness + startup
  withStartup: {
    http(path, port):: withStartupPreset(httpAction(path, port)),
    tcp(port):: withStartupPreset(tcpAction(port)),
    exec(cmd):: withStartupPreset(execAction(cmd)),
  },

  // u.probes.stateful.tcp(port) — readiness + startup (no liveness)
  stateful: {
    http(path, port):: statefulPreset(httpAction(path, port)),
    tcp(port):: statefulPreset(tcpAction(port)),
    exec(cmd):: statefulPreset(execAction(cmd)),
  },
}
