# VM option type definitions
{
  lib,
  flakeInputs,
  ...
}:

let

  mkOption = lib.mkOption;

  bool = lib.types.bool;
  str = lib.types.str;
  submodule = lib.types.submodule;
  enum = lib.types.enum;

  microvmOptions = flakeInputs.microvm.nixosModules.microvm-options;

  # ── VM type (per-VM entry under domain.clusters.<name>.vms.<name>) ──

  vmType.options = {

    host = mkOption {
      description = ''
        FQDN of the cluster machine that hosts this VM.

        Must resolve to an existing machine in the cluster config.
        Accepted forms:
          - "host1.example.com"  (full FQDN with domain suffix)
          - "host1.example"      (without domain suffix — suffix auto-appended)

        The resolver searches for a matching <machine>.<cluster> pair
        by trying all possible split points.
      '';
      type = str;
      example = "host1.example.com";
    };

    autostart = mkOption {
      description = ''
        Whether to start this VM automatically at host boot.
        Maps to microvm.autostart (or equivalent in future backends).
      '';
      type = bool;
      default = true;
    };

    restartIfChanged = mkOption {
      description = ''
        Whether to restart the VM's systemd services when the host
        is rebuilt and the VM configuration changes.
      '';
      type = bool;
      default = true;
    };

    backend = mkOption {
      description = "Virtualization backend configuration.";
      type = submodule {
        options = {
          type = mkOption {
            description = "Virtualization backend to use.";
            type = enum [
              "microvm"
              # future: "nixvirt", "nspawn"
            ];
            default = "microvm";
          };

          microvm = mkOption {
            description = "MicroVM-specific configuration.";
            type = submodule (
              {
                lib,
                pkgs,
                ...
              }:
              {
                options =
                  let
                    importedMicrovmOptions =
                      (import microvmOptions {
                        inherit lib pkgs;
                        config = {
                          microvm = { };
                        };
                      }).options.microvm;
                    # We need to delete the defaults because they depend on config that is not existent initially in the cluster config.
                    strippedMicrovmOptions = (lib.filterAttrsRecursive (
                      optionName: optionValue: optionName != "default" && optionName != "defaultText"
                    ) importedMicrovmOptions);
                  in
                   strippedMicrovmOptions
                  // 
                  {
                    shareNixStore = lib.mkOption {
                      description = ''
                        Whether to share the host's /nix/store with the microvm guest.
                        This is a convenience option that adds a 9p share of /nix/store
                        to the microvm configuration. It is enabled by default since most
                        users will want it, but can be disabled if you want to manage the
                        shares yourself or don't need access to the host's Nix store.
                      '';
                      type = lib.types.bool;
                      default = true;
                    };
                  };
              }
            );
            default = { };
          };
        };
      };
    };
  };

in
vmType
