local kubernetesDashboard = import 'dashboard/kubernetes-dashboard.libsonnet';
local u = import 'utils.libsonnet';

{
  dashboard: u.labelApp('kubernetes-dashboard', kubernetesDashboard.new()),
  admin: u.labelApp('kubernetes-dashboard', kubernetesDashboard.createAdmin()),
}
