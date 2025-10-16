{
  clusterInfo,
  selectors,
  roles,
  this,
}:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  etcdPort = 2379;
  etcdList = if roles ? etcd && roles.etcd != [ ] then roles.etcd else roles.controlPlane;

  #############################
  # Helper Functions

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;

  # corednsPolicies =
  #   map
  #     (r: {
  #       apiVersion = "abac.authorization.kubernetes.io/v1beta1";
  #       kind = "Policy";
  #       spec = {
  #         user = "system:coredns";
  #         namespace = "*";
  #         resource = r;
  #         readonly = true;
  #       };
  #     })
  #     [
  #       "endpoints"
  #       "services"
  #       "pods"
  #       "namespaces"
  #     ]
  #   ++ lib.singleton {
  #     apiVersion = "abac.authorization.kubernetes.io/v1beta1";
  #     kind = "Policy";
  #     spec = {
  #       user = "system:coredns";
  #       namespace = "*";
  #       resource = "endpointslices";
  #       apiGroup = "discovery.k8s.io";
  #       readonly = true;
  #     };
  #   };
in
{

  # Using ABAC for CoreDNS running outside of k8s
  # is more simple in this case than using kube-addon-manager
  # authorizationMode = [
  #   "RBAC"
  #   "Node"
  #   "ABAC"
  # ];
  # authorizationPolicy = corednsPolicies;

  etcd = {
    servers = map (node: mkUrl etcdPort node.fqdn) etcdList;
  };

}
