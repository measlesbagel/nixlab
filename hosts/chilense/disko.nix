{ ... }:
{
  disko.devices = {
    disk.main = {
      device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_4000GB_23402H801448";
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
        };
        "local/nix" = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        "safe/home" = {
          type = "zfs_fs";
          mountpoint = "/home";
        };
      };
    };
  };
}
