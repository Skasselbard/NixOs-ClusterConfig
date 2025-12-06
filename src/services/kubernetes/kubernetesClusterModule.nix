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

      kubeConfigs = {

        accountNames = mkOption {
          description = ''
            A list of account names for which kubeConfigs should be generated.
            Certificates with these names have to exists in your certDir.
          '';
          type = lib.types.listOf lib.types.str;
          default = [
            "admin"
            "super-admin"
          ];
        };

        apiServer = mkOption {
          description = ''
            Hostname to the api server (ip or fqdn) used in the generation scripts.
            By default kubernetes.<clusterName>.<suffix> will be used.
          '';
          type = lib.types.nullOr lib.types.str;
          default = null;
        };

        certDir = mkOption {
          description = ''
            Path to the certificates from which the kubeConfigs should be build.
            Certificates with the name <accountName>.cert should be stored in this path.
          '';
          type = lib.types.str;
          default = "./certificates/kubernetes/certs";
        };

        caPath = mkOption {
          description = "The path to the certificate authority that signed the used certificates.";
          type = lib.types.str;
          default = "./certificates/kubernetes/ca/kubernetes.crt";
        };

      };

      serviceAccount = {

        privateKeyPath = mkOption {
          description = "Path to the generated private key file.";
          type = lib.types.str;
          default = "./serviceAccount/sa.key";
        };

        publicKeyPath = mkOption {
          description = "Path to the generated public key file.";
          type = lib.types.str;
          default = "./serviceAccount/sa.pub";
        };

        encrypt = mkOption {
          description = "Encrypt the key with a passphrase";
          type = lib.types.bool;
          default = false;
        };

        algorithm = mkOption {
          description = "Algorithm to use for the key generation";
          type = lib.types.enum [
            "ed25519"
            "rsa-4096"
            "p384"
          ];
          default = "ed25519";
        };

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

    packages = {
      createKubeConfigs =
        { clusterConfig }:
        let
          controlPlaneMachines = clusterConfig.clusters.this.services.kubernetes.roles.controlPlane or [ ];
          clusterFqdn = clusterConfig.clusters.this.fqdn;
          clusterName = clusterConfig.clusters.this.name;
          kubeConfigs = clusterConfig.clusters.this.services.kubernetes.kubeConfigs;
          apiServer =
            if kubeConfigs.apiServer == null then "kubernetes.${clusterFqdn}" else kubeConfigs.apiServer;
        in
        if controlPlaneMachines != [ ] then
          (pkgs.writeShellScriptBin "createKubeConfigs" ''
            export PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
            for ACCOUNT_NAME in ${toString kubeConfigs.accountNames}; do
              ${pkgs.bash}/bin/bash ${./scripts/create-kubeconfigs.sh}\
                --role $ACCOUNT_NAME \
                --server https://${apiServer}:6443 \
                --cert-dir ${kubeConfigs.certDir} \
                --ca-path ${kubeConfigs.caPath} \
                --cluster-name ${clusterName} \
                --output-dir ./kubeConfigs
            done
          '')
        else
          pkgs.writeShellScriptBin "createKubeConfigs" "echo \"no control-plane machine is configured for this cluster\"";

      createServiceAccount =
        { clusterConfig }:
        let
          controlPlaneMachines = clusterConfig.clusters.this.services.kubernetes.roles.controlPlane or [ ];
          serviceAccountConfig = clusterConfig.clusters.this.services.kubernetes.serviceAccount;
        in
        if controlPlaneMachines != [ ] then
          (pkgs.writeShellScriptBin "createServiceAccount" ''
            set -euo pipefail
            export PATH=$PATH:${pkgs.openssl}/bin:${pkgs.jq}/bin
            export SA_KEY=${serviceAccountConfig.privateKeyPath}
            export SA_PUB=${serviceAccountConfig.publicKeyPath}
            export SA_ENCRYPT=${toString serviceAccountConfig.encrypt}
            export SA_ALG=${serviceAccountConfig.algorithm}

            echo "[INFO] Generating Service Account Keys"
            ${pkgs.bash}/bin/bash ${./scripts/create-sa-keys.sh}
          '')
        else
          pkgs.writeShellScriptBin "createServiceAccount" "echo \"no control-plane machine is configured for this cluster\"";
    };

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
