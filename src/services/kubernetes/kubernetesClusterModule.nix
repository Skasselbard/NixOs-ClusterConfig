{
  pkgs,
  clusterlib,
  lib,
  ...
}:
let

  add = clusterlib.add;
  filters = clusterlib.filters;

  forEach = lib.lists.forEach;
  concatStringsSep = lib.strings.concatStringsSep;

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
              etcdMachines
              ;
            control-plane-config = firstMachine.nixosConfiguration.config;
          };
          certData = certData-mapping.certData;
          certDate-json-file = certData-mapping.certDate-json-file;

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
                    ${pkgs.bash}/bin/bash ${./scripts/create-etcd-certs.sh} ${certDate-json-file}
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
                    ${pkgs.bash}/bin/bash ${./scripts/create-k8s-ca.sh} ${certDate-json-file}
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
                        if jq -e ".k8s.roles.\"$role\"" ${certDate-json-file}  >/dev/null; then
                          echo "[INFO] Generating kube-config for role: $role"
                          ${pkgs.bash}/bin/bash ${./scripts/create-k8s-cert.sh} "$role" ${certDate-json-file} 
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
                  (pkgs.writeShellScriptBin "createKubeConfigs" ''
                    mkdir -p certs
                    cd certs
                    PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
                    ${pkgs.bash}/bin/bash ${./scripts/create-kubeConfigs.sh} ${certDate-json-file}
                  '')
                else
                  pkgs.writeShellScriptBin "createKubeConfigs" "echo \"no control-plane machine is configured for this cluster\""
              else
                pkgs.writeShellScriptBin "createKubeConfigs" "echo \"kubernetes is not configured for this cluster\"";

          };
        }
      );

    in
    kubernetesScripts;
in
{
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
