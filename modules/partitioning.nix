# partition with disko https://github.com/nix-community/disko

{ pkgs, config, lib, ... }:
let
  # The disko version cannot be set in nix due to an infinit recursion problem:
  # We use the version for both a module in 'imports' and in 'config'.
  # However, config requires imports to be resolved, which is a problem when imports references config.
  #
  # As a workaround we get the disko version from a versions.json expected in the configuration 
  # root folder and use the "HIVE_ROOT" environment variable set by the hive.py script to resolve the versions.json.
  disko_source = with builtins;
    fetchTarball "https://github.com/nix-community/disko/archive/${
      (fromJSON (readFile (getEnv "HIVE_ROOT" + "/versions.json"))).disko
    }.tar.gz";
  disko = import disko_source { inherit lib; };
  disko_module = "${disko_source}/module.nix";
in {
  options = with lib;
    with types; {
      partitioning = {
        enable_disko = mkOption {
          type = bool;
          default = false;
          description = ''
            If set to true the 'config.disko' option (see disko docs https://github.com/nix-community/disko/blob/master/docs/INDEX.md) will be set based on the 'partitioning.format_disko' and 'partitioning.additional_disko' options from this module.
            This will generate a file system configuration according to the disko options.
            If this option is disabled the disko option is not set and the file system configuration has to be defined another way.
          '';
        };
        format_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description =
            "This disko definitions will be used to build a formating script and for the systems mounting configuration. See https://github.com/nix-community/disko/blob/master/docs/INDEX.md for disko documentation.";
        };
        additional_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description =
            "This disko definitions will be used in addition to the formatting definition to build the whole disko definition for mounting configuration. See https://github.com/nix-community/disko/blob/master/docs/INDEX.md for disko documentation.";

        };
      };
    };
  imports = [ ./setup.nix disko_module ];
  config = {
    setup.scripts = [
      # building a disko reformating script and adding it to the setup (iso) environment
      (pkgs.writeScriptBin "disko-format" (''
        echo "Format disk configured disko devicves?"
        echo "WARNING: all disk content will be erased if you select yes!"
        [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] &&  echo "Canceld formating disko config." && exit
        echo "Formatting disko config."
      '' + (disko.diskoScript { disko = config.partitioning.format_disko; }
        pkgs)))
      # Add another script to format the whole configuration for virgin drives
      (pkgs.writeScriptBin "disko-format-ALL" (''
        echo "Format disk ALL configured disko devicves?"
        echo "WARNING: all disk content will be erased if you select yes! This is the script for the ENTIRE configuration not just the format_disko configurtation!"
        [[ ! "$(read -e -p "Type 'FORMAT-ALL' to continue> "; echo $REPLY)" == "FORMAT-ALL" ]] &&  echo "Canceld formating entire disko config." && exit
        echo "Formatting entire disko config."
      '' + (disko.diskoScript {
        disko = (lib.attrsets.recursiveUpdate config.partitioning.format_disko
          config.partitioning.additional_disko);
      } pkgs)))
    ];
    setup.preScript =
      lib.mkIf config.partitioning.enable_disko [ "sudo disko-format" ];
    # merging formatting and additional disko attributes to make the final disko configuration
    disko = (lib.attrsets.recursiveUpdate config.partitioning.format_disko
      config.partitioning.additional_disko) // {
        # disable disko configuration if flag is set
        enableConfig = config.partitioning.enable_disko;
      };
  };
}
