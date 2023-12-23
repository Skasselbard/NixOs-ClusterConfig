{ host_config, rootPasswd ? "setup", rootPasswdHash ? null, rootSSHKeys ? [ ]
, lib, pkgs }: {
  # lib.debug.traceSeqN 3 config.users.users.tom

  imports = [ "${disko}/module.nix" ./ssh.nix ./partitioning.nix ];
  # TODO: boot
  networking.hostName = host_config.networking.hostName;
  networking.interfaces =
    host_config.networking.interfaces; # TODO: find good filters
  users.users.root = {
    isNormalUser = true;
    password = rootPasswd;
    hashedPassword = lib.mkIf (rootPasswdHash != null) rootPasswdHash;
    openssh.authorizedKeys.keys = mkDefault [ config.sshKey ];
    shell = nushellFull;
    openssh.authorizedKeys.keys = rootSSHKeys;
  };
  partitioning = {
    # force disable disko to use installer iso file system configuration
    enable_disko = lib.mkForce false;
    format_disko = host_config.partitioning.format_disko;
    additional_disko = host_config.partitioning.additional_disko;
  };
  # # copy configuration for the mini system
  # environment.etc = {
  #   "nixos/modules" = { source = ../modules; };
  # } //
  #   # copy all files to '/etc/nixos/files' that are specified in setup.files
  #   lib.listToAttrs (map (path: {
  #     name = "nixos/files/${builtins.baseNameOf path}";
  #     value = { source = path; };
  #   }) host_config.setup.files);

  environment.systemPackages = with pkgs;
    with builtins;
    let
      nixos_version = pkgs.writeScriptBin "nixos_version"
        "${pkgs.jq}/bin/jq -r .nixos /etc/nixos/versions.json";
      # wrap install scripts in a package
      setup = writeScriptBin "setup" (readFile ../scripts/setup.sh);
      preSetup = writeScriptBin "pre-setup" (lib.strings.concatLines
        (lib.lists.unique host_config.setup.preScript));
      postSetup = writeScriptBin "post-setup" (lib.strings.concatLines
        (lib.lists.unique host_config.setup.postScript));
    in [
      bash
      btrfs-progs
      dig
      emacs
      git
      jq
      nixfmt
      preSetup
      postSetup
      setup
      zfs
      nixos_version
    ] ++
    # add setup scripts specified in setup.scripts
    host_config.setup.scripts;

  system.stateVersion = "23.11";

  #############

  ######
  # imports = [ "${_disko_source}/module.nix" ../scripts/iso.nix ];
  # host_config = {
  #   inherit _disko_source admin interface ip setup partitioning colmena;
  #   networking.hostName = host_config.networking.hostName;
  #   environment.etc = {
  #     # "nixos/configuration.nix" = {
  #     # source = /home/tom/repos/nix-blueprint/generated/lianli/mini_sys.nix;
  #     # }; TODO:
  #     "nixos/versions.json" = {
  #       text = "{nixos: nixos-23.11, k3s: v1.27.4-k3s1, disko: v1.1.0}";
  #     };
  #   };
  # };

}
