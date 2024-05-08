{ pkgs }:
with pkgs.lib;
with pkgs.lib.types;
let

  usertype = {
    homeManagerModules = mkOption {
      description = mdDoc ''
        A list of modules included by homeManager.

        Home manager has its own module system which is evaluated independantly from the NixOs modules.
        However, the form of home manager modules is identical to NixOs modules.

        This list will not be evaluated by the cluster configuration.
        It will be directly forwarded to home manager on the corresponding machines in the cluster.
      '';
      type = listOf raw;
      default = [ ];
    };

    systemConfig = mkOption {
      description = ''
        An attribute containing NixOs options defined for 'config.users.users.\${name}.

        This configuration is copied to the corresponding user for each machine in the cluster.
      '';
      type = attrsOf raw;
      default = { };
      example = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
      };
    };

  };
in { options = usertype; }
