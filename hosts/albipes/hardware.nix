{ lib, ... }:
{
  # UGreen NASync (Pentium Gold 8505); uplink: AQC113 10GbE (atlantic).
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  boot.kernelModules = [
    "kvm-intel"
    # UGOS leaves it armed at 1200s, so systemd must feed it.
    "it87_wdt"
  ];
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "60s";
    RebootWatchdogSec = "5min";
  };

  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
