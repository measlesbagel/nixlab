{ ... }:
{
  disko.devices = {
    disk = {
      os = {
        device = "/dev/disk/by-id/nvme-YSR128GHLCV-E3C-1_511240604199002263";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      data-a = {
        device = "/dev/disk/by-id/wwn-0x5000cca2a9c1f116";
        type = "disk";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "tank";
            };
          };
        };
      };
      data-b = {
        device = "/dev/disk/by-id/wwn-0x5000cca2a9c20dec";
        type = "disk";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "tank";
            };
          };
        };
      };
    };

    zpool.rpool = {
      type = "zpool";
      options.ashift = "12";
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
        acltype = "posixacl";
        xattr = "sa";
        mountpoint = "none";
        canmount = "off";
      };
      datasets = {
        "local/root" = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
      };
    };

    zpool.tank = {
      type = "zpool";
      mode = "mirror";
      options.ashift = "12";
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
        acltype = "posixacl";
        xattr = "sa";
        mountpoint = "none";
        canmount = "off";
      };
      datasets = {
        media = {
          type = "zfs_fs";
          mountpoint = "/tank/media";
          options.recordsize = "1M";
        };
        backups = {
          type = "zfs_fs";
          mountpoint = "/tank/backups";
        };
        objects = {
          type = "zfs_fs";
          mountpoint = "/tank/objects";
        };
        models = {
          type = "zfs_fs";
          mountpoint = "/tank/models";
          options.recordsize = "1M";
        };
        # atticd already zstd-compresses its chunks.
        nix-cache = {
          type = "zfs_fs";
          mountpoint = "/tank/nix-cache";
          options.compression = "off";
        };
      };
    };
  };
}
