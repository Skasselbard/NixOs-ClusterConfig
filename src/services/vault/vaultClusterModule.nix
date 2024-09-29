{
  pkgs,
  nixpkgs,
  clusterlib,
  ...
}:
let

  forEachAttrIn = clusterlib.forEachAttrIn;
  eval = clusterlib.eval;
  add = clusterlib.add;
  filters = clusterlib.filters;

  createDummyMachine =
    config: clusterName: clusterConfig:
    let

      # Build and evaluate a dummy cluster with a dummy machine to extract the vault configuration.
      #
      # The dummy machine will be evaluated and added to the nixosConfigurations of the dummy cluster.
      # From there we can read the actual evaluated config.
      #
      #
      # Additional thoughts:
      # This approach does only work this way, if the needed configuration is machine independent.
      # To extract machine dependent configurations, the actual machines have to be used instead of a dummy machine.
      # Machine dependent configurations may or may not trap evaluation in an infinite loop.
      #
      # Another approach to read machine dependent config might be, to evaluate the cluster given with 'config'.
      # However, to avoid infinite recursion, the clusterModule (this file) probably has to be deleted from 'config.modules'
      # Additionally the machines on wich the service (in this case vault) should be deployed need to be known.
      # This should be resolvable with the selectors defined in 'config.domain.clusters.${clusterName}.services.vault'
      dummyCluster = clusterlib.buildCluster {

        domain.suffix = config.domain.suffix;

        domain.clusters."${clusterName}" = {

          services.vault = {
            roles = {
              apiAddress = [ (filters.hostname "dummyMachine") ];
              clusterAddress = [ (filters.hostname "dummyMachine") ];
            };
            selectors = [ (filters.hostname "dummyMachine") ];
            definition = clusterConfig.services.vault.definition;
            extraConfig = clusterConfig.services.vault.extraConfig;
          };

          machines.dummyMachine = {
            system = "x86_64-linux";
            nixosModules = [ { imports = [ "${nixpkgs}/nixos/modules/profiles/base.nix" ]; } ];
          };

        };

      };

    in
    dummyCluster.nixosConfigurations.dummyMachine.config;

  deploymentAnnotation =
    config:
    let

      # build an iso package for each machine configuration 
      vaultScripts = add.clusterPackage config (
        clusterName: clusterConfig:
        let
          cfg = (createDummyMachine config clusterName clusterConfig).services.vault;

          scriptParams = {
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

          vault.createRootCertificate =
            if clusterConfig.services ? vault then
              (pkgs.writeShellScriptBin "createRootCertificate" ''
                PATH=$PATH:${pkgs.certstrap}/bin
                ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert root ''\'${builtins.toJSON scriptParams}''\' ''${@:1}
              '')
            else
              pkgs.writeScriptBin "createRootCertificate" "echo \"vault is not configured for this cluster\"";

          vault.createTlsCertificate =
            if clusterConfig.services ? vault then
              (pkgs.writeShellScriptBin "createTlsCertificate" ''
                PATH=$PATH:${pkgs.certstrap}/bin
                ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert intermediate ''\'${builtins.toJSON scriptParams}''\' ''${@:1}
              '')
            else
              pkgs.writeScriptBin "createRootCertificate" "echo \"vault is not configured for this cluster\"";

        }
      );

    in
    vaultScripts;
in
{
  config.extensions.deploymentTransformations = [ deploymentAnnotation ];
}
