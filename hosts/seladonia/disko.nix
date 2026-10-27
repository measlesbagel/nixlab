{ ... }:
{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-KLEVV_CRAS_C930_M.2_NVMe_SSD_1TB_RN003702";
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
          options.mountpoint = "legacy";
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.mountpoint = "legacy";
        };
        "safe/var-lib" = {
          type = "zfs_fs";
          mountpoint = "/var/lib";
          options.mountpoint = "legacy";
        };
        "safe/navidrome" = {
          type = "zfs_fs";
          mountpoint = "/var/lib/navidrome";
          options.mountpoint = "legacy";
        };
        "safe/postgres" = {
          type = "zfs_fs";
          mountpoint = "/var/lib/postgresql";
          options = {
            mountpoint = "legacy";
            recordsize = "8K";
            logbias = "throughput";
          };
        };
      };
    };
  };
}
