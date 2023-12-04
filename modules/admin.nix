{ lib, config, pkgs, ... }:

with lib;
with pkgs;
with builtins; {
  options = with types; {
    admin = {
      name = mkOption {
        type = str;
        default = "admin";
        description = lib.mdDoc ''
          Name of the admin user of the system.

          A user with this name will be created and added to the `wheel` group.
          The password of the user will be assigned to the value of `admin.hashedPassword` and
          the ssh keys configured in `admin.sshKeys` will be configured for remote access.
        '';
      };
      hashedPwd = mkOption {
        type = nullOr str;
        default = null;
        description = lib.mdDoc ''
          A password hash that should be used for the admin user.
          Can be generated e.g. wit `mkpasswd -m sha-512`.
        '';
      };
      sshKeys = mkOption {
        type = listOf str;
        description = lib.mdDoc ''
          A list of ssh public keys that are used for remote access.

          Both the root user and the user configured with `admin.name` will be configured with this list.
        '';
      };
    };
  };
  config = {
    users.extraUsers = with config.admin; {
      root = { openssh.authorizedKeys.keys = sshKeys; };

      "${name}" = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPassword = hashedPwd;
        openssh.authorizedKeys.keys = sshKeys;
      };
    };
  };
}
