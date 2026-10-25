{ lib, ... }:
{
  # Ryzen 7 7800X3D + RTX 4090; uplink: RTL8159 10GbE USB adapter (r8152).
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [
    "kvm-amd"
    # Some firmware leaves it disabled; `wdctl` shows whether it bound.
    "sp5100_tco"
  ];
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "60s";
    RebootWatchdogSec = "5min";
  };

  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  # USB autosuspend kept dropping the RTL8159 and Bluetooth until a reboot.
  boot.kernelParams = [ "usbcore.autosuspend=-1" ];

  # The in-tree r8152 only reaches 10G on the RTL8159 with this PHY firmware.
  # Its kernel >= 7.2 assertion matters: the kernel picker falls back below
  # 7.2 if nixpkgs drops it before ZFS supports anything newer.
  hardware.rtl8159.enable = true;
}
