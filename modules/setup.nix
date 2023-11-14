{ lib, ... }: {
  options = with lib.types; {
    setup = {
      preScript = {
        type = nullOr str;
        default = null;
        description = ''
          A shell scrpt that is executed before the setup instructions are started in the installation iso.
          Usefull e.g. for partittioning.
          The script will be exported in /bin in the installation iso.
          The script will not be present after the installation nor in the final machine config.
        '';
      };
      postScript = {
        type = nullOr str;
        default = null;
        description = ''
          A shell scrpt that is executed after the setup instructions are started in the installation iso.
          The script will be exported in /bin in the installation iso.
          The script will not be present after the installation nor in the final machine config.
        '';
      };
      # isoIncludes = TODO: jhgfjg
      # miniSystemIncludes = TODO:
    };
  };
}
