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
          cfg = firstMachine.nixosConfiguration.config.services.vault;

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
                let
                  connectionData = forEach vaultMachines (machine: {
                    host = machine.deployment.targetHost;
                    user =
                      if machine.deployment ? targetUser && machine.deployment.targetUser != null then
                        machine.deployment.targetUser + "@"
                      else
                        "";
                  });

                  initScript = (pkgs.writeShellScript "initialize-vault" cfg.initialization.script);
                in
                pkgs.writeScriptBin "initialize-vault-remote" ''
                  connectionData=(
                    ${concatStringsSep " " (map (data: "${data.user}${data.host}") connectionData)}
                  )

                  script_path="${initScript.outPath}"

                  # SSH options
                  ssh_options="-o ConnectTimeout=5"

                  for conn in "''${connectionData[@]}"; do
                      echo "Attempting to connect to $conn..."
                      if ssh $ssh_options "$conn" "echo 'Connected successfully to $conn'"; then
                          echo "Running script $script_path on $conn"
                          ssh $ssh_options "$conn" 'bash -s' < "$script_path"
                          exit 0
                      else
                          echo "Unable to reach $conn, trying next entry..."
                      fi
                  done

                  echo "All machines are unreachable."
                  exit 1
                ''
              else
                pkgs.writeScriptBin "initialize-vault-remote" "echo \"vault is not configured for this cluster\"";
          };
        }
      );

    in
    vaultScripts;
in
{
  config.extensions.transformations.deploymentTransformations = [ deploymentAnnotation ];
}
