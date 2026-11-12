{ ... }:
{
  services.smartd = {
    enable = true;
    autodetect = true;
  };

  homelab.vmTest.unverifiable."smartd.service" = "QEMU disks have no SMART data";
}
