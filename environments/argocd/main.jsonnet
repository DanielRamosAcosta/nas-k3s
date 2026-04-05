local argocd = import 'system/argocd/argocd.libsonnet';
local u = import 'utils.libsonnet';

// Import all environments to discover apps dynamically.
// When adding a new environment, add an entry here.
local envs = [
  u.argocd.env(import '../arr/spec.json', import '../arr/main.jsonnet'),
  u.argocd.env(import '../auth/spec.json', import '../auth/main.jsonnet'),
  u.argocd.env(import '../business/spec.json', import '../business/main.jsonnet'),
  u.argocd.env(import '../databases/spec.json', import '../databases/main.jsonnet'),
  u.argocd.env(import '../media/spec.json', import '../media/main.jsonnet'),
  u.argocd.env(import '../monitoring/spec.json', import '../monitoring/main.jsonnet'),
  u.argocd.env(import '../system/spec.json', import '../system/main.jsonnet'),
];

local apps = u.argocd.buildAppsMap(envs, { argocd: 'argocd' });

u.Environment({
  argocd: argocd.new(apps),
})
