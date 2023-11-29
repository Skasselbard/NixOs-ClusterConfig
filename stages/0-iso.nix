{ config, lib, pkgs, ... }: {
  imports =
    [ <nixpkgs/nixos/modules/profiles/base.nix> ../modules/default.nix ];

  # force disable disko to use installer iso file system configuration
  partitioning.enable_disko = lib.mkForce false;
  # copy configuration for the mini system
  environment.etc = {
    "nixos/modules" = { source = ../modules; };
  } //
    # copy all files to '/etc/nixos/files' that are specified in setup.files
    lib.listToAttrs (map (path: {
      name = "nixos/files/${builtins.baseNameOf path}";
      value = { source = path; };
    }) config.setup.files);

  environment.systemPackages = with pkgs;
    with builtins;
    let
      nixos_version = pkgs.writeScriptBin "nixos_version"
        "${pkgs.jq}/bin/jq -r .nixos /etc/nixos/versions.json";
      # wrap install scripts in a package
      setup = writeScriptBin "setup" (readFile ../scripts/setup.sh);
      preSetup = writeScriptBin "pre-setup"
        (lib.strings.concatLines (lib.lists.unique config.setup.preScript));
      postSetup = writeScriptBin "post-setup"
        (lib.strings.concatLines (lib.lists.unique config.setup.postScript));
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
    config.setup.scripts;

}
