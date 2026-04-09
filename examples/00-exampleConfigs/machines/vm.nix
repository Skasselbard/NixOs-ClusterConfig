# VM machine configuration template.
#
# This is a standard NixOS configuration — no ClusterConfig features here.
# It is parameterized so each VM can have a different IP and disk device.
#
# This file is called from ../default.nix like:
#   (import ./machines/vm.nix) { ip = "192.168.122.200"; osDevicePath = "/dev/disk/by-id/virtio-OS"; }

{
  # Function parameters — these differ per VM instance
  ip, # The static IP address for eth0
  osDevicePath,
  # The disk device path for the OS installation
  # In libvirt: configure a VirtIO disk with Serial "OS",
  # then it appears as /dev/disk/by-id/virtio-OS.
}:

# Standard NixOS module function
{ config, ... }:
{

  imports = [ ./vm-hardware-configuration.nix ];

  system.stateVersion = "24.05";

  # --- Boot configuration ---
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;

  # Enable flakes (required for ClusterConfig to work)
  nix.extraOptions = "experimental-features = nix-command flakes";

  # --- SSH ---
  # Enable SSH so we can deploy to this machine remotely.
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;

  # --- Networking ---
  # We expect two interfaces on the VM connected to the same virtual network.
  # Using predictable interface names can be unpredictable in VMs :p (PCI location varies),
  # so we disable them. The interfaces will be named eth0, eth1, etc.
  networking.usePredictableInterfaceNames = true;

  # eth0: static IP for predictable cluster communication.
  # This is the address used in deployment.targetHost and in the DNS service.
  networking.interfaces."eth0" = {
    ipv4.addresses = [
      {
        address = ip;
        prefixLength = 24;
      }
    ];
  };

  # eth1: DHCP for internet access via NAT.
  # This gives the VM internet access for downloading packages during deployment.
  networking.interfaces."eth1".useDHCP = true;

  # --- Disk partitioning (disko) ---
  # Disko is used for declarative partitioning.
  # This config defines a simple GPT layout with an EFI system partition and a root partition.
  # See: https://github.com/nix-community/disko/blob/master/example/simple-efi.nix
  disko = {
    devices = {
      disk = {
        main = {
          device = osDevicePath;
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                type = "EF00";
                size = "500M";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
            };
          };
        };
      };
    };
  };

}
