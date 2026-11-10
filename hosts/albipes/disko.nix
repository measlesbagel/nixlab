{ ... }:
let
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk = {
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
          btrfs = {
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  inherit mountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  inherit mountOptions;
                };
              };
            };
          };
        };
      };
    };

    # One RAID1 filesystem across both drives, made from data-b's partition;
    # data-a's is partitioned first, as disko goes through disks by name.
    data-a = {
      device = "/dev/disk/by-id/wwn-0x5000cca2a9c1f116";
      type = "disk";
      content = {
        type = "gpt";
        partitions.btrfs.size = "100%";
      };
    };
    data-b = {
      device = "/dev/disk/by-id/wwn-0x5000cca2a9c20dec";
      type = "disk";
      content = {
        type = "gpt";
        partitions.btrfs = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "-f"
              "--data"
              "raid1"
              "--metadata"
              "raid1"
              "/dev/disk/by-partlabel/disk-data-a-btrfs"
            ];
            # Top level, for btrbk (modules/snapshots.nix).
            mountpoint = "/mnt/tank";
            inherit mountOptions;
            subvolumes = {
              "@media" = {
                mountpoint = "/tank/media";
                inherit mountOptions;
              };
              "@backups" = {
                mountpoint = "/tank/backups";
                inherit mountOptions;
              };
              "@objects" = {
                mountpoint = "/tank/objects";
                inherit mountOptions;
              };
              "@models" = {
                mountpoint = "/tank/models";
                inherit mountOptions;
              };
              "@snapshots" = { };
            };
          };
        };
      };
    };
  };
}
