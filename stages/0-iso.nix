{ config, lib, pkgs, ... }: {
  imports = [
    <nixpkgs/nixos/modules/profiles/base.nix>
    ../modules/default.nix
    ../modules/setup.nix
  ];

  # copy configuration for the mini system
  # environment.etc = {
  #   "nixos/modules" = { source = modules; };
  #   "nixos/partitioning.nix" = { source = ../../partitioning/{{hostname}}.nix; };
  #   "nixos/configuration.nix" = { source = TODO: path/to/mini_sys.nix; };
  #   TODO: hardware configuration
  # };

  environment.systemPackages =
    # let 
    #   # wrap install scripts in a package
    #   setup = pkgs.writeScriptBin "setup" ''
    #     {{setup_script|indent(6)}}
    #   '';
    #   preSetup = pkgs.writeScriptBin "pre-setup" config.setup.preScript;
    #   postSetup = pkgs.writeScriptBin "post-setup" config.setup.postScript;
    # in
    with pkgs; [
      bash
      btrfs-progs
      dig
      emacs
      # (pkgs.callPackage "${disko}/package.nix" { }) # disko
      git
      jq
      nixfmt
      # preSetup
      # postSetup
      # setup
      zfs
    ];

}
