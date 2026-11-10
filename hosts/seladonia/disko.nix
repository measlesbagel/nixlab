{ ... }:
let
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk.main = {
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
        btrfs = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            # Top level, for btrbk (modules/snapshots.nix).
            mountpoint = "/mnt/btr_pool";
            inherit mountOptions;
            subvolumes = {
              "@root" = {
                mountpoint = "/";
                inherit mountOptions;
              };
              "@nix" = {
                mountpoint = "/nix";
                inherit mountOptions;
              };
              "@var-lib" = {
                mountpoint = "/var/lib";
                inherit mountOptions;
              };
              "@navidrome" = {
                mountpoint = "/var/lib/navidrome";
                inherit mountOptions;
              };
              "@postgres" = {
                mountpoint = "/var/lib/postgresql";
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
