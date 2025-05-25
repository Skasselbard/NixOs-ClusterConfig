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
          # get the attrset of the curent cluster
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
          firstMachine = builtins.head etcdMachines;
          # get the config from the picked machines
          cfg = firstMachine.nixosConfiguration.config.services.kubernetes;

          certificateScriptParams = {
            certData = {
              org = cfg.cluster.certificates.generation.organization;
              orgUnit = cfg.cluster.certificates.generation.organizationUnit;
              country = cfg.cluster.certificates.generation.country;
              province = cfg.cluster.certificates.generation.province;
              locality = cfg.cluster.certificates.generation.locality;
              domain = cfg.cluster.certificates.generation.domain;
              issuer = cfg.cluster.certificates.generation.issuer;
            };
            role = clusterName + "-certification";
            ca = {
              name = "etcd-ca";
              passPhrase = "";
            };
            server = {
              name = "etcd-server";
              domains = map (machine: machine.annotations.fqdn) etcdMachines;
              ips = [ ]; # We don't add ips and only use host names fro verification
              passPhrase = "";
            };
            peer = {
              name = "etcd-peer";
              domains = map (machine: machine.annotations.fqdn) etcdMachines;
              ips = [ ]; # We don't add ips and only use host names fro verification
              passPhrase = "";
            };
          };

        in
        {

          kubernetes = # lib.debug.traceSeqN 5 certificateScriptParams
            {
              createEtcdCertificates =
                if clusterConfig.services ? kubernetes then
                  if etcdMachines != [ ] then
                    let
                      certConfigJson = pkgs.writeText "etcd-cert-config.json" (builtins.toJSON certificateScriptParams);
                    in
                    (pkgs.writeShellScriptBin "createRootCertificate" ''
                      PATH=$PATH:${pkgs.certstrap}/bin:${pkgs.jq}/bin
                      ${pkgs.bash}/bin/bash ${./scripts/create-etcd-certs.sh} ${certConfigJson}
                    '')
                  else
                    pkgs.writeShellScriptBin "createRootCertificate" "echo \"no etcd machine is configured for this cluster\""
                else
                  pkgs.writeShellScriptBin "createRootCertificate" "echo \"kubernetes is not configured for this cluster\"";

            };
        }
      );

    in
    kubernetesScripts;
in
{
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
