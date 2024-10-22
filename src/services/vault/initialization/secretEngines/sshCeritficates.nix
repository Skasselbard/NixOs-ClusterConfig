{
  lib,
  pkgs,
  config,
  ...
}:

let

  sshInitScript = ''

    # Enable the SSH secrets engine
    echo "Enabling SSH secrets engine..."
    vault secrets enable -path=ssh ssh || echo "SSH secrets engine already enabled."

    # Configure SSH roles
    echo "Configuring SSH roles..."
    ${lib.concatMapStringsSep "\n" (role: ''
      echo "Creating role: ${role.name}"
      vault write ssh/roles/${role.name} \
        key_type=${role.keyType} \
        default_user=${role.defaultUser} \
        cidr_list="${role.cidrList}" \
        allowed_users="${role.allowedUsers}" || echo "Role ${role.name} already exists."
    '') config.services.vault.sshRoles}

  '';

in
{

  options.services.vault.initialization.secretsEngines.sshCertificates = {

    enable = lib.mkEnableOption "Enable the SSH secrets engine in Vault.";

    roles = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      default = [ ];
      description = "List of SSH roles to be configured in Vault.";
    };

    initScript = lib.mkOption {
      type = lib.types.str;
      default = sshInitScript;
      description = "The Vault SSH secrets engine initialization script.";
    };
  };

}
