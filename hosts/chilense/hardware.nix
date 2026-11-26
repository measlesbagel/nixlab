{ config, lib, ... }:
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
  boot.kernelParams = [
    "amd_iommu=on"
    "usbcore.autosuspend=-1"
  ];

  # The in-tree r8152 only reaches 10G on the RTL8159 with this PHY firmware,
  # from kernel 7.2 on (the module asserts it).
  hardware.rtl8159.enable = true;

  # Desktop runs on the 7800X3D iGPU (0c:00.0); the RTX 4090 (01:00.0) serves
  # Linux games via `nvidia-offload` and dynamically unbinds for VFIO VMs.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    # Persistenced holds /dev/nvidia* open and blocks dynamic VFIO unbind.
    nvidiaPersistenced = false;
    powerManagement.enable = false;
    nvidiaSettings = true;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      amdgpuBusId = "PCI:12@0:0:0";
      nvidiaBusId = "PCI:1@0:0:0";
    };
  };
}
