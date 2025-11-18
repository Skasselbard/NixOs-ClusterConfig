{
  pkgs,
  lib,
  nixhelm,
  nix-kube-generators,
}:
let
  remove = lib.lists.remove;
  flatten = lib.lists.flatten;

  # Create URL from hostname and port
  mkUrl = port: address: "https://${address}:${toString port}";
  mkUrls = port: addresses: map (address: mkUrl port address) addresses;

  getEtcdList = roles: if roles ? etcd && roles.etcd != [ ] then roles.etcd else roles.controlPlane;
  getControlPlaneList = roles: roles.controlPlane;
  getWorkerList = roles: roles.worker or [ ];
  getRoleNodes = roles: role: roles."${role}" or [ ];

  getControlPlaneIps =
    roles: flatten (map (machine: parseRealIps machine.ips) (getControlPlaneList roles));
  getControlPlaneFqdns = roles: (map (node: node.fqdn) (getControlPlaneList roles));

  getEtcdIps = roles: flatten (map (machine: parseRealIps machine.ips) (getEtcdList roles));
  getEtcdFqdns = roles: (map (node: node.fqdn) (getEtcdList roles));

  # get a list of ips excluding dhcp configurations
  parseRealIps =
    ips:
    let
      ipList = flatten (lib.attrsets.mapAttrsToList (name: value: value) ips);
    in
    remove "dhcp" ipList;

  helm =
    let
      chartDownloads = nixhelm.charts { inherit pkgs; };
      kubeGeneratorsLib = nix-kube-generators.lib { inherit pkgs; };
    in
    {
      charts =
        {
          namespace ? null,
          values ? { },
          includeCRDs ? true,
          kubeVersion ? "v${pkgs.kubernetes.version}",
          apiVersions ? [ ],
          extraHelmOpts ? [ ],
        }:
        lib.mapAttrs (
          repo: repoCharts:
          lib.mapAttrs (
            chartName: _:
            kubeGeneratorsLib.fromHelm {
              inherit
                namespace
                values
                includeCRDs
                kubeVersion
                apiVersions
                ;
              extraOpts = extraHelmOpts;
              name = chartName;
              chart = chartDownloads."${repo}"."${chartName}";
            }
          ) repoCharts
        ) chartDownloads;
    };

in
{
  inherit
    mkUrl
    mkUrls

    getControlPlaneList
    getControlPlaneIps
    getControlPlaneFqdns

    getEtcdList
    getEtcdIps
    getEtcdFqdns

    getRoleNodes

    getWorkerList

    helm
    ;
}
