{
  lib,
  config,
  ...
}:

let
  str = lib.types.str;
  flatten = lib.lists.flatten;
  forEach = lib.lists.forEach;

  mkOption = lib.mkOption;

  # Cluster-level vault service config
  vaultServiceCfg = config.clusterConfig.clusters.this.services.vault;
  certs = vaultServiceCfg.certificates;
  selectors = vaultServiceCfg.selectors;
  certOrg = certs.organization;

  # Resolve certificate paths (same logic as vaultService.nix)
  basePath = certs.path.serverBase;
  caRootCertName =
    if certs.path.caRootCertName != "" then certs.path.caRootCertName else "${certOrg}-root";
  rootCaFile = basePath + caRootCertName + ".crt";

  # Build the list of API endpoints from all vault machines' listeners
  getServiceAddresses =
    searchRole: host:
    if host ? serviceAddresses then
      builtins.filter (elem: elem.role == searchRole) host.serviceAddresses
    else
      [ ];

  getListeners =
    host:
    let
      listeners = getServiceAddresses "vault-listener" host;
    in
    if listeners == [ ] then
      [
        {
          address = vaultServiceCfg.listenerAddress;
          port = vaultServiceCfg.listenerPort;
        }
      ]
    else
      listeners;

  clusterFqdn = config.clusterConfig.clusters.this.fqdn;
  hostFqdn = host: "${host.name}.vault.${clusterFqdn}";
  hostEndpoints =
    host: forEach (getListeners host) (listener: "https://${hostFqdn host}:${toString listener.port}");
  endpoints = flatten (forEach selectors (host: hostEndpoints host));

  initScript = ''
    set -e

    # Securely prompt for the Vault token
    read -s -p "Enter Vault Token: " VAULT_TOKEN
    echo

    if [ -z "$VAULT_TOKEN" ]; then
      echo "Error: Vault token cannot be empty."
      exit 1
    fi

    # Function to check if a Vault instance is available
    check_vault() {
      local vault_addr=$1
      echo "Checking Vault at $vault_addr ..."
      export VAULT_ADDR=$vault_addr

      if VAULT_CACERT="${rootCaFile}" vault status >/dev/null 2>&1; then
        echo "Connected to Vault at $vault_addr"
        return 0
      else
        echo "Vault at $vault_addr is not available."
        return 1
      fi

    }

    # Iterate over the Vault URIs and connect to the first available instance
    for uri in ${(lib.concatStringsSep " " endpoints)}; do
      if check_vault "$uri"; then
        break
      fi
    done

    if [ -z "$VAULT_ADDR" ]; then
      echo "Error: Could not connect to any Vault instance."
      exit 1
    fi

      VAULT_CACERT=${rootCaFile}

      # $ {
      #   let
      #     cfg = config.services.vault;
      #     sshCertificatesCfg = cfg.secretsEngines.sshCertificates;
      #     sshCertificateInit = if sshCertificatesCfg.enable then sshCertificatesCfg.initScript else "";
      #   in
      #   sshCertificateInit
      # }

      echo "Vault SSH secrets engine initialization complete."
  '';
in
{
  options.services.vault.initialization.script = mkOption {
    type = str;
    default = initScript;
  };

  imports = [ ./secretEngines/sshCeritficates.nix ];

}
