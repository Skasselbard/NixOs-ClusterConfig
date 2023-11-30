{ pkgs ? import <nixpkgs> { }, lib ? import <nixpkgs/lib>, host-definition
, disko_url, ... }:

let
  eval = (lib.evalModules {
    modules = [
      host-definition
      # Setting dummy values and downloading disko source to make the module system happy
      {
        config.nixpkgs.hostPlatform = "x86_64-linux";
        options.disko = lib.mkOption { type = lib.types.attrs; };
        config._disko_source = builtins.fetchTarball disko_url;
      }
    ] ++ (import <nixpkgs/nixos/modules/module-list.nix>);
  });
in if (eval.config.setup.bootLoader.customConfig != null) then {
  boot.loader = eval.config.setup.bootLoader.customConfig;
} else {
  boot.loader = {
    grub.device = eval.config.boot.loader.grub.device;
    grub.devices = eval.config.boot.loader.grub.devices;
    grub.efiInstallAsRemovable =
      eval.config.boot.loader.grub.efiInstallAsRemovable;
    grub.efiSupport = eval.config.boot.loader.grub.efiSupport;
    grub.enable = eval.config.boot.loader.grub.enable;
    grub.enableCryptodisk = eval.config.boot.loader.grub.enableCryptodisk;
    grub.zfsSupport = eval.config.boot.loader.grub.zfsSupport;
    systemd-boot.enable = eval.config.boot.loader.systemd-boot.enable;
    efi.canTouchEfiVariables = eval.config.boot.loader.efi.canTouchEfiVariables;
  };
}
