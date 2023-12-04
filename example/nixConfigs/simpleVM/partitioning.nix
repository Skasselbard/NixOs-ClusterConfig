{
  partitioning = {
    enable_disko = true;
    format_disko.devices = {
      disk = {
        nixos = {
          device = "/dev/disk/by-id/virtio-OS"; # depends on your vm configuration
          type = "disk";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                type = "EF00";
                size = "512M";
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
