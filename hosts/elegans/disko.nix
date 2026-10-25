{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/disk/by-id/nvme-ESL01TBTLCZ-27J2-TYN_5P1250820001003706";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          # Several generations of NVIDIA kernel + initrd.
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        # Some model loads peak above RAM. Random encryption re-runs mkswap
        # each boot, so the header matches the kernel's page size (4K or 64K).
        swap = {
          size = "16G";
          content = {
            type = "swap";
            randomEncryption = true;
          };
        };
        # Not ZFS: the ARC would compete with the GPU for the 128 GB pool.
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
}
