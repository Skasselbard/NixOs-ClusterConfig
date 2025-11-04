{
  pkgs,
  clusterlib,
  lib,
  ...
}:
let

  add = clusterlib.add;
  filters = clusterlib.filters;

  options = clusterlib.mkAnnotation {
    annotationPath = "kubernetes.nodeLabels";
    description = "A set of labels that will be added to the node when registered in the kubernetes cluster.";
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example = {
      "environment" = "production";
      "zone" = "us-west-1a";
    };
  };

  deploymentAnnotation =
    config:
    let

      kubernetesScripts = add.clusterPackage config (
        clusterName: clusterConfig:
        let
          # get the attrset of the current cluster
          cluster = config.domain.clusters.${clusterName};
          # get all machines selected by the kubernetes service definition
          kubernetesMachines =
            filters.resolveDefinitions cluster.services.kubernetes.selectors clusterName
              config;
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
              pkgs
              lib
              controlPlaneMachines
              workerMachines
              etcdMachines
              ;
            control-plane-config = firstMachine.nixosConfiguration.config;
          };
          certData = certData-mapping.certData;
          certData-json-file = certData-mapping.certDate-json-file;

        in
        {
          kubernetes = {

            createEtcdCertificates =
              if clusterConfig.services ? kubernetes then
                if etcdMachines != [ ] then
                  (pkgs.writeShellScriptBin "createEtcdCertificates" ''
                    mkdir -p certs
                    cd certs
                    PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
                    ${pkgs.bash}/bin/bash ${./scripts/create-etcd-certs.sh} ${certData-json-file}
                  '')
                else
                  pkgs.writeShellScriptBin "createEtcdCertificates" "echo \"no etcd machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createEtcdCertificates" "echo \"kubernetes is not configured for this cluster\"";

            createK8sCA =
              if clusterConfig.services ? kubernetes then
                if controlPlaneMachines != [ ] then
                  (pkgs.writeShellScriptBin "createK8sCA" ''
                    mkdir -p certs
                    cd certs
                    PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
                    ${pkgs.bash}/bin/bash ${./scripts/create-k8s-ca.sh} ${certData-json-file}
                  '')
                else
                  pkgs.writeShellScriptBin "createK8sCA" "echo \"no control-plane machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createK8sCA" "echo \"kubernetes is not configured for this cluster\"";

            createK8sCerts =
              let
                roles = builtins.attrNames certData.k8s.roles;
              in
              if clusterConfig.services ? kubernetes then
                if controlPlaneMachines != [ ] then
                  (pkgs.writeShellScriptBin "createK8sCert" ''
                    set -euo pipefail
                    mkdir -p certs
                    cd certs
                    PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin

                      for role in ${builtins.concatStringsSep " " roles}; do
                        if jq -e ".k8s.roles.\"$role\"" ${certData-json-file}  >/dev/null; then
                          echo "[INFO] Generating kube-config for role: $role"
                          ${pkgs.bash}/bin/bash ${./scripts/create-k8s-cert.sh} "$role" ${certData-json-file} 
                        else
                          echo "[INFO] Skipping role: $role (not in config)"
                        fi
                      done
                  '')
                else
                  pkgs.writeShellScriptBin "createK8sCert" "echo \"no control-plane machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createK8sCert" "echo \"kubernetes is not configured for this cluster\"";

            createKubeConfigs =
              if clusterConfig.services ? kubernetes then
                if controlPlaneMachines != [ ] then
                  let
                    apiServer = firstMachine.annotations.fqdn;
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
  options.domain = options.domain; # For some reason, setting options directly (inherit options;) triggers an infinite recursion
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
