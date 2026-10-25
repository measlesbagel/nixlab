{ ... }:
{
  # ASUS Ascent GX10 (GB10); uplink: RTL8127 10GbE (r8127), dual ConnectX-7.
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
  ];
}
