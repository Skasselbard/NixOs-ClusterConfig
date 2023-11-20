{ lib, ... }: {
  options = with lib;
    with lib.types; {
      setup = {
        preScript = mkOption {
          type = nullOr str;
          default = null;
          description = ''
            A shell script that is executed before the setup instructions are started in the installation iso.
            Usefull e.g. for partittioning.
            The script will be exported in /bin in the installation iso.
            The script will not be present after the installation nor in the final machine config.
          '';
        };
        postScript = mkOption {
          type = nullOr str;
          default = null;
          description = ''
            A shell script that is executed after the setup instructions are started in the installation iso.
            The script will be exported in /bin in the installation iso.
            The script will not be present after the installation nor in the final machine config.
          '';
        };
        files = mkOption {
          type = listOf path;
          default = [ ];
          description = ''
            Files that should be availabe during the installation phase.
            These files will be copied to /etc/nixos/files.
            TODO: Check if folders work out of the box as well.
          '';
        };
        scripts = mkOption {
          type = listOf path;
          default = [ ];
          description = ''
            Files that should be available as executable scripts during the installation phase.
            These files will be turned into a derivation by 'pkgs.writeScriptBin' and added
            to 'environment.systemPackages' with the basename of the given path as script name.
          '';
        };
      };
    };
}
