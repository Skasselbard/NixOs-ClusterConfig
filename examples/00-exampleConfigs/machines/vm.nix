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
{ config, lib, ... }:
{

  imports = [ ./vm-hardware-configuration.nix ];

  system.stateVersion = "26.05";

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
  # The VM uses a single interface (eth0) with a static IP for cluster communication.
  # This same interface also reaches the internet via NAT on the host.
  # Using predictable interface names can be unpredictable in VMs (PCI location varies),
  # so we disable them. The interface will be named eth0.
  networking.usePredictableInterfaceNames = true;

  # Single interface with a static IP.
  # This address is used in deployment.targetHost and in the DNS service.
  # Internet access for package downloads goes through the same interface
  # via NAT configured on the host machine (see NAT hint below).
  networking.interfaces."eth0" = {
    ipv4.addresses = [
      {
        address = ip;
        prefixLength = 24;
      }
    ];
  };
  networking.defaultGateway = "192.168.122.1";

  # --- Host NAT Hint ---
  # The VM needs internet access (e.g. to download packages during deployment).
  # Since there is only one interface with a static IP, NAT must be set up on
  # the host machine to forward traffic from the VM's network.
  #
  # On a NixOS host with libvirt, add something like this to your host config:
  #
  #   networking.nat = {
  #     enable = true;
  #     externalInterface = "enp0s3";    # your host's internet-facing interface
  #     internalInterfaces = [ "virbr0" ]; # the libvirt default NAT network
  #   };
  #
  # The exact interface names depend on your host setup. The key point is that
  # traffic from VMs on the virtual network (192.168.122.0/24) is masqueraded
  # through the host's external interface. If your host is not NixOS, configure
  # iptables/nftables masquerading accordingly.

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
