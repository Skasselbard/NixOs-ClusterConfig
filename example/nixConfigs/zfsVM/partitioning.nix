{ pkgs, lib, config, ... }:
{
  # nedded for zfs; generate random: ``head -c4 /dev/urandom | od -A none -t x4``
  networking.hostId = "0d376921";
  services.zfs.autoScrub.enable = true;
  # script to fix ntfs partitioning after partial formatting
  setup.scripts = [
    (pkgs.writeScriptBin "fix_windows"
      "sudo ntfsfix /dev/disk/by-partlabel/windows")
  ];
  partitioning = {
    enable_disko = true;
    format_disko.devices = {
      disk = {
        # disk with linux and efi partition
        linux = {
          type = "disk";
          device = "/dev/disk/by-id/virtio-OS";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                label = "EFI";
                size = "512M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
              };
              zfs = {
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "root";
                };
              };
            };
          };
        };
        # disk for dualboot with windows
        windows = {
          type = "disk";
          device = "/dev/disk/by-id/virtio-WINDOWS";
          content = {
            type = "gpt";
            # Only half of the disk is used for windows.
            # No partition content is defined here (see further down for the definition)
            # to keep the disk content on windows.
            # However, rewriting the partition table also deletes the file system information.
            # For this reaseon we have to recover the filesystem with `fix_windows` script at the top.
            partitions = {
              windowsReserved = {
                name = "primary";
                label = "windows";
                start = "0%";
                end = "10000M";
              };
              # The rest is added to the zfs pool
              # This makes disko partitioning harder (for now)
              zfs = {
                start = "10001M";
                size = "100%";
                content = {
                  type = "zfs";
                  pool = "root";
                };
              };
            };
          };
        };
      };
      # zpool configuration with encryption
      zpool = {
        root = {
          mode = ""; # just striping "RAID0"
          options = {
            # ssd options
            ashift = "13";
            autotrim = "on";
          };
          rootFsOptions = {
            compression = "zstd-4";
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "prompt";
            "com.sun:auto-snapshot" = "false";
            atime = "off";
          };
          mountpoint = "/";
          datasets = {
            home = {
              type = "zfs_fs";
              mountpoint = "/home";
              options."com.sun:auto-snapshot" = "true";
            };
            temp = {
              # https://wiki.archlinux.org/title/ZFS#/tmp
              type = "zfs_fs";
              mountpoint = "/tmp";
              options = {
                compression = "zstd-5";
                sync = "disabled";
                setuid = "off";
                devices = "off";
              };
            };
            nix = {
              type = "zfs_fs";
              mountpoint = "/nix";
              options = {
                compression = "zstd-19";
                atime = "off";
              };
            };
          };
        };
      };
    };
    # This configuration is not added to the default format script.
    # However the `disko-format-ALL` script will include it.
    # The content will be merged with `partitioning.disko_format`, so duplacated
    # options should be identical
    additional_disko.devices = {
      disk = {
        windows = {
          content = {
            partitions = {
              windowsReserved = {
                # Here we can define the ntfs file system
                content = {
                  type = "filesystem";
                  format = "ntfs";
                  mountpoint = "/mnt/windows";
                };
              };
            };
          };
        };
      };
    };
  };
}
