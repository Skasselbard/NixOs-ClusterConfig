{ pkgs, clusterlib, ... }:
let

  add = clusterlib.add;
  filters = clusterlib.filters;

  deploymentAnnotation =
    config:
    let

      # build an iso package for each machine configuration 
      vaultScripts = add.clusterPackage config (
        clusterName: clusterConfig:
        let
          # get the attrset of the curent cluster 
          cluster = config.domain.clusters.${clusterName};
          # get all machines selected by the vault service definition
          vaultMachines = filters.resolveDefinitions cluster.services.vault.selectors clusterName config;
          # pick an arbitrary machine from the vault machines
          firstMachine = builtins.head vaultMachines;
          # get the config from the picked machines
          cfg = pkgs.lib.debug.traceSeqN 1 firstMachine firstMachine.nixosConfiguration.config.services.vault;

          certificateScriptParams = {
            certData = {
              org = cfg.cluster.certificates.organization;
              orgUnit = cfg.cluster.certificates.organizationUnit;
              country = cfg.cluster.certificates.country;
              province = cfg.cluster.certificates.province;
              locality = cfg.cluster.certificates.locality;
              domain = cfg.cluster.certificates.domain;
              issuer = cfg.cluster.certificates.issuer;
            };
            role = clusterName + "-certification";
            certPath = cfg.cluster.certificates.path.localBase;
            rootCert = {
              name = cfg.cluster.certificates.path.caRootCertName;
              passPhrase = "";
            };
            intermediate = {
              name = cfg.cluster.certificates.path.vaultCertName;
              passPhrase = "";
            };
          };

        in
        {

          vault = {
            createRootCertificate =
              if clusterConfig.services ? vault then
                (pkgs.writeShellScriptBin "createRootCertificate" ''
                  PATH=$PATH:${pkgs.certstrap}/bin
                  ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert root ''\'${builtins.toJSON certificateScriptParams}''\' ''${@:1}
                '')
              else
                pkgs.writeScriptBin "createRootCertificate" "echo \"vault is not configured for this cluster\"";

            createTlsCertificate =
              if clusterConfig.services ? vault then
                (pkgs.writeShellScriptBin "createTlsCertificate" ''
                  PATH=$PATH:${pkgs.certstrap}/bin
                  ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert intermediate ''\'${builtins.toJSON certificateScriptParams}''\' ''${@:1}
                '')
              else
                pkgs.writeScriptBin "createTlsCertificate" "echo \"vault is not configured for this cluster\"";

            initialize =
              if clusterConfig.services ? vault then
                (pkgs.writeShellScriptBin "initialize-vault" cfg.initialization.script)
              else
                pkgs.writeScriptBin "initialize-vault" "echo \"vault is not configured for this cluster\"";
          };
        }
      );

    in
    vaultScripts;
in
{
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
