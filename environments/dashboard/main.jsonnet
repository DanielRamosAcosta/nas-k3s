local kubernetesDashboard = import 'dashboard/kubernetes-dashboard.libsonnet';

{
  dashboard: kubernetesDashboard.new(),
  admin: kubernetesDashboard.createAdmin(),
}
