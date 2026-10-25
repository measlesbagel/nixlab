{ ... }:
{
  # ConnectX-7 ports run point to point to the other Spark, with jumbo frames
  # so RoCE runs at a 4096 MTU instead of 1024.
  networking.interfaces = {
    # By name: the NVIDIA kernel's r8127 is not mainline's driver.
    enP7s7.mtu = 9000;
    enp1s0f0np0 = {
      mtu = 9000;
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.100.11";
          prefixLength = 24;
        }
      ];
    };
    enP2p1s0f0np0 = {
      mtu = 9000;
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.101.11";
          prefixLength = 24;
        }
      ];
    };
  };
}
