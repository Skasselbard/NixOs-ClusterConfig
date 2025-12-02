{
  pkgs,
  clusterlib,
  lib,
  flakeInputs,
  ...
}:
let
  mkOption = lib.mkOption;

  add = clusterlib.add;
  filters = clusterlib.filters;

  nixhelm = flakeInputs.nixhelm;
  nix-kube-generators = flakeInputs.nix-kube-generators;

  kubeLib = import ./kubelib.nix {
    inherit
      pkgs
      lib
      nix-kube-generators
      nixhelm
      ;
  };

  addFlakeInputs =
    config:
    add.nixosModule config (
      _: _: _: {
        _module.args = {
          inherit # flake inputs needed for the kubeLib of the kubernetesService
            nixhelm
            nix-kube-generators
            ;
        };
      }
    );

  certOptions = (import ./certificates/clusterOptions.nix) { inherit lib; };

  deploymentAnnotation =
    config:
    let

      kubernetesScripts = add.clusterPackage config (
        clusterName: clusterConfig:
        let
          # get the attrset of the current cluster
          cluster = config.domain.clusters.${clusterName};
          clusterFqdn = cluster.fqdn;

          # get all ControlPLane nodes
          controlPlaneMachines =
            if builtins.hasAttr "controlPlane" cluster.services.kubernetes.roles then
              filters.resolveDefinitions cluster.services.kubernetes.roles.controlPlane clusterName config
            else
              (builtins.trace "Warning: kubernetes controlPlane role is not defined" [ ]);

          workerMachines =
            if builtins.hasAttr "worker" cluster.services.kubernetes.roles then
              filters.resolveDefinitions cluster.services.kubernetes.roles.controlPlane clusterName config
            else
              (builtins.trace "Warning: kubernetes worker role is not defined" [ ]);

          etcdMachines =
            let
              etcdRoles =
                if builtins.hasAttr "etcd" cluster.services.kubernetes.roles then
                  filters.resolveDefinitions cluster.services.kubernetes.roles.etcd clusterName config
                else
                  [ ];
            in
            if etcdRoles == [ ] then controlPlaneMachines else etcdRoles;
          # pick an arbitrary machine from the kubernetes machines
          firstMachine = builtins.head controlPlaneMachines;

          certData-mapping = import ./control-plane/cert-data-mapper.nix {
            inherit
              clusterFqdn
              controlPlaneMachines
              etcdMachines
              kubeLib
              lib
              pkgs
              workerMachines

              ;
            control-plane-config = firstMachine.nixosConfiguration.config;
          };
          certData = certData-mapping.certData;
          certData-json-file = certData-mapping.certDate-json-file;

        in
        {
          kubernetes = {

            createKubeConfigs =
              if clusterConfig.services ? kubernetes then
                if controlPlaneMachines != [ ] then
                  let
                    apiServer = "kubernetes.${cluster.fqdn}";
                  in
                  (pkgs.writeShellScriptBin "createKubeConfigs" ''
                    mkdir -p certs
                    PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
                    ${pkgs.bash}/bin/bash ${./scripts/create-kubeconfigs.sh}\
                      --role admin \
                      --server https://${apiServer}:6443 \
                      --cert-dir ./certs \
                      --ca-name k8s-ca \
                      --cluster-name ${clusterName} \
                      --output-dir ./kubeconfigs 
                  '')
                else
                  pkgs.writeShellScriptBin "createKubeConfigs" "echo \"no control-plane machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createKubeConfigs" "echo \"kubernetes is not configured for this cluster\"";

            createServiceAccount =
              if clusterConfig.services ? kubernetes then
                if controlPlaneMachines != [ ] then
                  (pkgs.writeShellScriptBin "createServiceAccount" ''
                    set -euo pipefail
                    mkdir -p certs
                    cd certs
                    PATH=$PATH:${pkgs.openssl}/bin:${pkgs.jq}/bin
                    echo "[INFO] Generating Service Account Keys"
                    ${pkgs.bash}/bin/bash ${./scripts/create-sa-keys.sh} --config ${certData-json-file} --alg p384
                  '')
                else
                  pkgs.writeShellScriptBin "createServiceAccount" "echo \"no control-plane machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createServiceAccount" "echo \"kubernetes is not configured for this cluster\"";
          };
        }
      );

    in
    kubernetesScripts;

in
{
  config.extensions.transformations.clusterTransformations = [ addFlakeInputs ];
  # config.extensions.transformations.deploymentTransformations = [ deploymentAnnotation ];
  config.extensions.clusterServices.kubernetes = {

    defaultModule = import ./kubernetesService.nix;

    roles = [
      "controlPlane"
      "worker"
      "etcd"
    ];

    options = {

      certificates = certOptions.serviceOptions;

      cniPlugin = mkOption {
        description = ''
          The CNI plugin to use for networking in the cluster.

          Supported options are "cilium".
        '';
        type = lib.types.enum [ "cilium" ];
        default = "cilium";
      };

      virtualIps = mkOption {
        description = ''
          A list of IP addresses the cluster should be available on.

          You can add a netmask suffix to the ip.
        '';
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "10.0.0.1"
          "192.168.200.20/24"
        ];
      };

    };

    late.config.accounts =
      { clusterConfig }: (import ./accounts/defaultAccounts.nix { inherit lib clusterConfig kubeLib; });

  };

  config.extensions.clusterMachine.options.kubernetes = {

    certificates = certOptions.machineOptions;

    nodeLabels = mkOption {
      description = "A set of labels that will be added to the node when registered in the kubernetes cluster.";
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "environment" = "production";
        "zone" = "us-west-1a";
      };
    };

    keepalived.virtualIpInterface = mkOption {
      description = ''
        The Interfaces that will be used for Virtual Address assignment.

        If left empty for a machine with the keepalived role an error will be raised.
      '';
      type = lib.types.str;
      example = "eth0";
      default = "";
    };

    keepalived.priority = mkOption {
      description = ''
        The priority of the virtual router.

        The router with the highest priority will be the master of the keepalived cluster and assume the virtual IP.
        Routers with lesser priority will be used as backup.
        The priorities for each machine should be different.
        The highest priority is 255 ond the lowest is 0.

        Machines without an annotated priority but with the keepalived role will be assigned with a free priority beginning by 255
        and decreasing for the next machines in order of the role definition.
      '';
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 253;
      apply =
        value:
        if value != null && (value < 0 || value > 255) then
          throw "services.keepalived.priority must be between 0 and 255 (got ${toString value})"
        else
          value;
    };

  };
}
