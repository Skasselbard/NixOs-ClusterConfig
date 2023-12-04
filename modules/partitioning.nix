# partition with disko https://github.com/nix-community/disko

{ pkgs, config, lib, ... }:
let disko = import config._disko_source { inherit lib; };
in {
  options = with lib;
    with types; {
      _disko_source = mkOption {
        type = nullOr path;
        description = lib.mdDoc "Automatically set. Please dont use.";
        default = null;
        internal = true;
      };
      partitioning = {
        enable_disko = mkOption {
          type = bool;
          default = false;
          description = lib.mdDoc ''
            If set to true the `config.disko` option (see [disko docs](https://github.com/nix-community/disko/blob/master/docs/INDEX.md)) will be set based on the `partitioning.format_disko` and `partitioning.additional_disko` options from this module.
            This will generate a file system configuration according to the disko options.
            If this option is disabled the disko option is not set and the file system configuration has to be defined another way.
          '';
        };
        format_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description = lib.mdDoc
            "This disko definitions will be used to build a formating script and for the systems mounting configuration (see [disko docs](https://github.com/nix-community/disko/blob/master/docs/INDEX.md)).
            The script will be added to `$PATH` and executable with `disko-format`.
            It will be executed running the `setup` script (but can be skipped).";
          example.devices = {
            disk = {
              nixos = {
                device = "/dev/disk/by-id/virtio-OS";
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    boot = {
                      type = "EF00";
                      size = "512M";
                      content = {
                        type = "filesystem";
                        format = "vfat";
                        mountpoint = "/boot";
                      };
                    };
                    root = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/";
                      };
                    };
                  };
                };
              };
            };
          };
        };
        additional_disko = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description = lib.mdDoc
            "This disko definitions will be used in addition to the formatting definition to build the whole disko definition for mounting configuration (see [disko docs](https://github.com/nix-community/disko/blob/master/docs/INDEX.md)).
            Additionally a script with the combined configuration from `partitioning.format_disko` and `partitioning.additional_disko` will be created.
            The script will be added to `$PATH` and executable with `disko-format-ALL`.
            It will not be executed with the `setup` script";
          example.devices = {
            disk = {
              other = {
                device = "/dev/disk/by-id/virtio-WINDOWS";
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    data = {
                      size = "100%";
                      content = {
                        type = "filesystem";
                        format = "ext4";
                        mountpoint = "/var/data";
                      };
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  imports = [ ./setup.nix ];
  config = {
    setup.scripts = [
      # building a disko reformating script and adding it to the setup (iso) environment
      (pkgs.writeScriptBin "disko-format" (''
        echo "Format configured disko devicves?"
        echo "WARNING: all disk content will be erased if you select yes!"
        [[ ! "$(read -e -p "Y/n> "; echo $REPLY)" == [Yy]* ]] &&  echo "Canceld formating disko config." && exit
        echo "Formatting disko config."
      '' + (disko.diskoScript { disko = config.partitioning.format_disko; }
        pkgs)))
      # Add another script to format the whole configuration for virgin drives
      (pkgs.writeScriptBin "disko-format-ALL" (''
        echo "Format ALL configured disko devicves?"
        echo "WARNING: all disk content will be erased if you select yes! This is the script for the ENTIRE configuration not just the format_disko configurtation!"
        [[ ! "$(read -e -p "Type `FORMAT-ALL` to continue> "; echo $REPLY)" == "FORMAT-ALL" ]] &&  echo "Canceld formating entire disko config." && exit
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
