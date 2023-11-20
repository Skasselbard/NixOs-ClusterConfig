{ config, lib, pkgs, ... }: {
  imports = [
    <nixpkgs/nixos/modules/profiles/base.nix>
    ../modules/default.nix
    ../modules/setup.nix
  ];

  # copy configuration for the mini system
  environment.etc = {
    "nixos/modules" = { source = ../modules; };
    # "nixos/scripts"
  } //
    # copy all files to '/etc/nixos/files' that are specified in setup.files
    lib.listToAttrs (map (path: {
      name = "nixos/files/${builtins.baseNameOf path}";
      value = { source = path; };
    }) config.setup.files);

  # TODO: include extraconfig from nix key

  environment.systemPackages = with pkgs;
    with builtins;
    let
      # wrap install scripts in a package
      setup = writeScriptBin "setup" (readFile ../scripts/setup.sh);
      # preSetup = writeScriptBin "pre-setup" config.setup.preScript;
      # postSetup = writeScriptBin "post-setup" config.setup.postScript;
    in [
      bash
      btrfs-progs
      dig
      emacs
      git
      jq
      nixfmt
      # preSetup
      # postSetup
      setup
      zfs
    ] ++
    # add setup scripts specified in setup.scripts
    map (path: writeScriptBin (baseNameOf path) (readFile path))
    config.setup.scripts;

}
