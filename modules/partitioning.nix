# partition with disko https://github.com/nix-community/disko

{ pkgs, config, lib, ... }:
let disko = config._module.args.specialArgs.disko;
in {
  options = with lib;
    with lib.types; {
      partitioning = {
        ephemeral = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description = lib.mdDoc ''
            This disko definitions will be used to build a formating script and for the systems mounting configuration (see [disko docs](https://github.com/nix-community/disko/blob/master/docs/INDEX.md)).
            The script will be added to `$PATH` and executable with `disko-format`.
            It will be executed running the `setup` script (but can be skipped).
          '';
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
        persistent = mkOption {
          type = attrs; # TODO: can the type be loaded from disko?
          default = { };
          description = lib.mdDoc ''
            This disko definitions will be used in addition to the formatting definition to build the whole disko definition for mounting configuration (see [disko docs](https://github.com/nix-community/disko/blob/master/docs/INDEX.md)).
            Additionally a script with the combined configuration from `partitioning.format_disko` and `partitioning.additional_disko` will be created.
            The script will be added to `$PATH` and executable with `disko-format-ALL`.
            It will not be executed with the `setup` script
          '';
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
        ephemeral_script = mkOption {
          type = package;
          default =
            (disko.lib.diskoScript { disko = config.partitioning.ephemeral; }
              pkgs);
          description = ''
            Script to whipe and format the disko configuration specified by `partitioning.ephemeral`
          '';
        };
        persistent_script = mkOption {
          type = package;
          default = (disko.lib.diskoScript {
            disko = (lib.attrsets.recursiveUpdate config.partitioning.ephemeral
              config.partitioning.persistent);
          } pkgs);
          description = ''
            Script to whipe and format the disko configuration specified by `partitioning.ephemeral` AND `partitioning.persistent`.
          '';
        };
      };
    };
  config = {
    # merging ephemeral and persistent disko attributes to make the final disko configuration
    disko = (lib.attrsets.recursiveUpdate config.partitioning.ephemeral
      config.partitioning.persistent);
  };
}
