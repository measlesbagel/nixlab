{ lib, ... }:
{
  # Ryzen 9 8945HX mini PC; uplink: dual X710 10GbE SFP+ (i40e).
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
}
