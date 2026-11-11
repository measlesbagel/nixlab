{ ... }:
let
  mountOptions = [
    "compress=zstd"
    "noatime"
  ];
in
{
  disko.devices.disk.main = {
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
              "@home" = {
                mountpoint = "/home";
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
