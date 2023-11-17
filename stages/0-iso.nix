{ config, lib, pkgs, ... }: {
  imports = [
    <nixpkgs/nixos/modules/profiles/base.nix>
    ../modules/default.nix
    ../modules/setup.nix
  ];

  # copy configuration for the mini system
  environment.etc = {
    "nixos/modules" = { source = ../modules; };
  };

  environment.systemPackages =
    let 
      # wrap install scripts in a package
      setup = pkgs.writeScriptBin "setup" (builtins.readFile ../scripts/setup.sh);
      # preSetup = pkgs.writeScriptBin "pre-setup" config.setup.preScript;
      # postSetup = pkgs.writeScriptBin "post-setup" config.setup.postScript;
    in
    with pkgs; [
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
    ];

}
