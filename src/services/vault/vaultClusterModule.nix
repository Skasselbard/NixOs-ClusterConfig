{
  pkgs,
  lib,
  ...
}:
let
  mkOption = lib.mkOption;

  str = lib.types.str;
  enum = lib.types.enum;

  forEach = lib.lists.forEach;
  concatStringsSep = lib.strings.concatStringsSep;

  # Build the certificate parameters JSON used by the nushell certificates.nu script.
  # Resolves default values that depend on the evaluated cluster config.
  buildCertParams =
    clusterConfig:
    let
      vaultCfg = clusterConfig.clusters.this.services.vault;
      certs = vaultCfg.certificates;
      clusterName = clusterConfig.clusters.this.name;
    in
    {
      certData = {
        org = certs.organization;
        orgUnit = certs.organizationUnit;
        country = certs.country;
        province = certs.province;
        locality = certs.locality;
        domain = if certs.domain != "" then certs.domain else clusterConfig.clusters.this.fqdn;
        issuer =
          if certs.issuer != "" then certs.issuer else "${certs.organizationUnit}/${certs.organization}";
      };
      role = clusterName + "-certification";
      certPath = if certs.path.localBase != "" then certs.path.localBase else certs.path.serverBase;
      rootCert = {
        name =
          if certs.path.caRootCertName != "" then certs.path.caRootCertName else "${certs.organization}-root";
        passPhrase = "";
      };
      intermediate = {
        name =
          if certs.path.vaultCertName != "" then certs.path.vaultCertName else "${certs.organization}-vault";
        passPhrase = "";
      };
    };

in
{
  config.extensions.clusterServices.vault = {

    # The NixOS module applied to every machine selected by the vault service.
    # Configures the Vault server, TLS, Raft storage, clustering, and firewall.
    defaultModule = import ./vaultService.nix;

    # No roles needed — all vault machines are peers in the Raft cluster.
    roles = [ ];

    # Cluster-level options for the vault service.
    # These are available under: domain.clusters.<name>.services.vault.<option>
    # And inside NixOS modules as: config.clusterConfig.clusters.this.services.vault.<option>
    options = {

      enableUi = lib.mkEnableOption "Vault web UI (https://developer.hashicorp.com/vault/docs/configuration#ui)";

      logLevel = mkOption {
        type = enum [
          "trace"
          "debug"
          "info"
          "warn"
          "error"
        ];
        default = "info";
        description = "Vault log level (https://developer.hashicorp.com/vault/docs/configuration#log_level)";
      };

      certificates = {

        organization = mkOption {
          type = str;
          description = "Organization name for certificate generation.";
        };

        organizationUnit = mkOption {
          type = str;
          description = "Organization unit for certificate generation.";
        };

        country = mkOption {
          type = str;
          description = "Country code for certificate generation.";
        };

        province = mkOption {
          type = str;
          description = "Province / state for certificate generation.";
        };

        locality = mkOption {
          type = str;
          description = "Locality / city for certificate generation.";
        };

        domain = mkOption {
          type = str;
          default = "";
          description = "Domain for certificate generation. Defaults to the cluster FQDN.";
        };

        issuer = mkOption {
          type = str;
          default = "";
          description = "Issuer name for certificate generation. Defaults to orgUnit/org.";
        };

        path = {

          serverBase = mkOption {
            type = str;
            default = "/var/lib/vault/certs/";
            description = "Base path on the server where certificates are stored.";
          };

          localBase = mkOption {
            type = str;
            default = "";
            description = "Local path where certificate scripts look for certs. Defaults to serverBase.";
          };

          caRootCertName = mkOption {
            type = str;
            default = "";
            description = "Name of the root CA certificate file (without extension). Defaults to <org>-root.";
          };

          vaultCertName = mkOption {
            type = str;
            default = "";
            description = "Name of the Vault TLS certificate file (without extension). Defaults to <org>-vault.";
          };

          vaultKeyName = mkOption {
            type = str;
            default = "";
            description = "Name of the Vault TLS key file (without extension). Defaults to <org>-vault.";
          };
        };
      };

      listenerAddress = mkOption {
        type = str;
        default = "0.0.0.0";
        description = "Address the Vault listener binds to.";
      };

      listenerPort = mkOption {
        type = lib.types.port;
        default = 8200;
        description = "Port the Vault listener binds to.";
      };

    };

    # Cluster-level packages: available under .#<cluster>.vault.<command>
    packages = {

      # Generate a root CA certificate using certstrap.
      createRootCertificate =
        { clusterConfig }:
        let
          vaultService = clusterConfig.clusters.this.services.vault or null;
          certParams = buildCertParams clusterConfig;
        in
        if vaultService != null then
          pkgs.writeShellScriptBin "createRootCertificate" ''
            PATH=$PATH:${pkgs.certstrap}/bin
            ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert root '${builtins.toJSON certParams}' "''${@:1}"
          ''
        else
          pkgs.writeScriptBin "createRootCertificate" ''echo "vault is not configured for this cluster"'';

      # Generate a TLS certificate for Vault, signed by the root CA.
      createTlsCertificate =
        { clusterConfig }:
        let
          vaultService = clusterConfig.clusters.this.services.vault or null;
          certParams = buildCertParams clusterConfig;
        in
        if vaultService != null then
          pkgs.writeShellScriptBin "createTlsCertificate" ''
            PATH=$PATH:${pkgs.certstrap}/bin
            ${pkgs.nushell}/bin/nu ${./certificates.nu} create cert intermediate '${builtins.toJSON certParams}' "''${@:1}"
          ''
        else
          pkgs.writeScriptBin "createTlsCertificate" ''echo "vault is not configured for this cluster"'';

      # Run the Vault initialization script on the first reachable vault machine.
      initialize =
        { clusterConfig }:
        let
          vaultService = clusterConfig.clusters.this.services.vault or null;
          vaultMachines = vaultService.selectors or [ ];
          firstMachine = if vaultMachines != [ ] then builtins.head vaultMachines else null;

          connectionData = forEach vaultMachines (machine: {
            host = machine.deployment.targetHost;
            user =
              if machine.deployment ? targetUser && machine.deployment.targetUser != null then
                machine.deployment.targetUser + "@"
              else
                "";
          });

          initScript =
            if firstMachine != null then
              pkgs.writeShellScript "initialize-vault" firstMachine.config.services.vault.initialization.script
            else
              pkgs.writeShellScript "initialize-vault" "echo 'no vault machines configured'";
        in
        if vaultService != null && vaultMachines != [ ] then
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
          pkgs.writeScriptBin "initialize-vault-remote" ''echo "vault is not configured for this cluster"'';
    };

  };

}
