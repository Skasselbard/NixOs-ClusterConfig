# Shared example configurations.
#
# This file is imported by all example flake.nix files.
# It centralizes machine configs, secrets, and Home Manager modules
# so they can be reused across examples without duplication.
#
# Usage in a flake.nix:
#   configurations = (import ../00-exampleConfigs) { inherit pkgs; };
#   machines = configurations.machines;
#   secrets = configurations.secrets;
#   homeModules = configurations.homeModules;
{ pkgs, ... }:
let
  # The disk device path depends on your hypervisor and VM configuration.
  # For libvirt/QEMU with a VirtIO disk named "OS":
  #   The device appears as /dev/disk/by-id/virtio-OS
  # Adjust this if your hypervisor uses a different naming scheme.
  osDevicePath = "/dev/disk/by-id/virtio-OS";
in
{

  # Password hashes and SSH keys for the example users.
  # WARNING: These are PUBLIC example secrets. In a real project,
  # restrict access to your secrets directory!
  secrets = import ./secrets;

  # Machine configurations for three VMs.
  # Each VM gets the same base config (vm.nix) but with a different static IP.
  machines = {

    vm0 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.200";
    };

    vm1 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.201";
    };

    vm2 = (import ./machines/vm.nix) {
      inherit osDevicePath;
      ip = "192.168.122.202";
    };

  };

  # Home Manager modules for per-user configuration.
  # Used in examples 03 (Home Manager) and 04 (Secret Deployment).
  homeModules = {
    # Base module that sets home.stateVersion (required for all users when
    # any user uses Home Manager).
    default = import ./homeManager/default.nix;
    # Starship shell prompt configuration.
    starship = (import ./homeManager/starship.nix) { inherit pkgs; };
  };

}
