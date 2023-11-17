# Template for the minimal system installed from the boot medium.
#
# The complete system is installed with colmena, so the mini system
# should at least have the network configured correctly.
# You can add additional configuration by TODO: .
#
# WARNING: The mini system cannot reference paths from your local folder structure since
# it is copied from the installation medium to the host machine.
# All options must be self contained or reachable from the network.

{ config, ... }:{
  imports = [
    ./modules
    ./hardware-configuration.nix
    "${disko}/module.nix"
    ./partitioning.nix
  ];

  {{common_config}}
  {{extra_config}}

  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;
  {% if not legacy -%}
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  {%- else %}
  # boot.loader.grub.device = "/dev/disk/by-partlabel/disk-nixos-boot";
  {%- endif %}
}