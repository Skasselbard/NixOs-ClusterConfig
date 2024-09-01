{
  imports = [ ./vm-hardware-configuration.nix ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.enable = true;
  nix.extraOptions = ''
    # tarball-ttl = 0
    experimental-features = nix-command flakes'';

  networking.useDHCP = true;

  programs.zsh.enable = true;

  disko = {
    # disko configuration
    # from examples: https://github.com/nix-community/disko/blob/master/example/simple-efi.nix
    devices = {
      disk = {
        main = {
          device = "/dev/disk/by-id/virtio-OS";
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
