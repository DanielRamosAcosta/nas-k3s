local argocd = import 'system/argocd.libsonnet';

// These client IDs are not secrets - they're public identifiers
// The actual values come from the OIDC setup with Authelia
{
  argocd: argocd.new(
    clientID='yYqSsmaevMLFs5iCoYtDwjLdZ~DZ-g~5rYMEtdIrR82WxNhVectjCoCd1EgncpKiMrDdmI0T',
    cliClientID='T2qqr-u2jcUAt04xyLD2Oz.7ialdW5NdF21VOFYub1kW3AkxAWh~6mU4EHcufhdpXig77yhH',
  ),
}
