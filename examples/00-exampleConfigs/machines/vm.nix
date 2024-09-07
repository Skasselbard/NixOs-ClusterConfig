{ # function parameters to build different vms

ip, # The ip address configured for the eth0 interface
osDevicePath # The path to the device where the os schould be installed on.
# The device path depends on the kind and name of the drive given in your hipervisor.
# For example in libvirt: if you Configure a VirtIO Disk with Serial 'OS' (in the advanced options)
#   libvirt will call your device "virtio-OS" and 
#   Linux will make it available by name under "/dev/disk/by-id/virtio-OS".

}:
{ pkgs, config, ... }: {
  imports = [ ./vm-hardware-configuration.nix ];

  system.stateVersion = "24.05";

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  nix.extraOptions = ''
    # tarball-ttl = 0
    experimental-features = nix-command flakes'';

  # SSH configuration
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = config.services.openssh.ports;

  # We expect two interfaces on the vm connected to the same network.
  # This will be always eth0 and eth1 in legacy style interface names.
  # This is handy for vm definitions where the interfaces can be at
  # arbitrary pci locations, which makes the new predictable
  # interfaces rather unpredictable :p
  networking.usePredictableInterfaceNames = true;
  # eth0 will be static, so that we can connect to predictable ips
  networking.interfaces."eth0" = {
    ipv4.addresses = [{
      address = ip;
      prefixLength = 24;
    }];
  };
  # eht1 will use dhcp to make nat-ing to the outside world easy
  networking.interfaces."eth1".useDHCP = true;

  disko = {
    # disko configuration
    # from examples: https://github.com/nix-community/disko/blob/master/example/simple-efi.nix
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
