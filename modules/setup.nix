{ pkgs, lib, ... }: {
  options = with lib;
    with lib.types; {
      setup = {
        preScript = mkOption {
          type = listOf str;
          default = [ ];
          description = lib.mdDoc ''
            A set of shell commands that are executed before the setup instructions are started in the installation iso.

            The commands will be concatenated to a script which will be exported in /bin in the installation iso as `pre-setup`.
            During the pre-script phase the hardware-configuration was NOT generated and all nioxos files are still only in /etc/nixos.
            The script will not be present after the installation nor in the final machine config.
          '';
          example = [ "echo 'hello setup'" ];
        };
        postScript = mkOption {
          type = listOf str;
          default = [ ];
          description = lib.mdDoc ''
            A set of shell commands that are executed after the setup instructions are started in the installation iso.

            The commands will be concatenated to a script which will be exported in /bin in the installation iso as `post-setup`.
            During the post-script phase the hardware-configuration was already generated and all nioxos files are both in /etc/nixos and in /mnt/etc/nixos.
            The script will not be present after the installation nor in the final machine config.
          '';
          example = [ "sudo poweroff" ];
        };
        files = mkOption {
          type = listOf path;
          default = [ ];
          description = lib.mdDoc ''
            Files that should be availabe during the installation phase.
            These files will be copied to /etc/nixos/files.
            TODO: Check if folders work out of the box as well.
          '';
        };
        scripts = mkOption {
          type = listOf path;
          default = [ ];
          description = lib.mdDoc ''
            Files that should be available as executable scripts during the installation phase.

            These files will be turned into a derivation by `pkgs.writeScriptBin` and added
            to `environment.systemPackages` with the basename of the given path as script name.
            This means that they will be in `$PATH` and executable by name.
          '';
          example = (pkgs.writeScriptBin "greetings"
            ''echo 'Hi\nI was called by typing "greetings"' '');
        };
        bootLoader.customConfig = mkOption {
          type = nullOr attrs;
          default = null;
          description = lib.mdDoc ''
            Custom configuration for the nixOs `boot.loader` options used in the mini system.

            The boot configuration for the mini system has to function. By default (if this option is `null`) specific options from your configuration (see `scripts/boot-crawler.nix`) are copied to the `boot.loader` configuration of the generated mini system.
            If this behavior does not work for you, you can set this option to be copied instead.
          '';
          example = { grub.extraConfig = "smth smth"; };
        };
      };
    };
}
