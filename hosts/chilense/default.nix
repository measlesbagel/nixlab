# TODO(provisioning): Wayland compositor lands at migration.
{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "chilense";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.vfio = {
    enable = true;
    vmNames = [ "win11" ];
    igpuPciAddress = "0000:0c:00.0";
    # IOMMU group 12: RTX 4090 VGA + HDA audio.
    gpuDevices = [
      "0000:01:00.0"
      "0000:01:00.1"
    ];
    # Optional isolated peripheral passthrough for 3D scanning:
    # - 0000:09:00.0 (group 19): onboard MediaTek MT7922 Wi-Fi 6E (BT stays on 0a:00.0)
    # - 0000:0c:00.4 (group 26): empty CPU USB 3.1 10 Gbps controller
    vm.extraPciDevices = [
      "0000:09:00.0"
      "0000:0c:00.4"
    ];
    # Shrink 32 GiB ReBAR (BAR1 = 2^15 MiB) to 256 MiB (2^8 MiB) for OVMF,
    # then restore 32 GiB when the GPU returns to Linux.
    resizeBar = {
      device = "0000:01:00.0";
      resource = 1;
      guestSize = 8;
      hostSize = 15;
    };
  };

  homelab.snapshots."/mnt/btr_pool/@home" = "state";
  homelab.replicate = [ "/mnt/btr_pool/@home" ];

  hjem = {
    extraModules = [ inputs.hjem-rum.hjemModules.default ];
    users.measles = import ../../home/measles;
  };

  homelab.vmTest.checks.hjem = ''
    with subtest("measles's login shell finds every hjem package"):
        for tool in ${
          builtins.toJSON (map (package: baseNameOf (lib.getExe package)) config.hjem.users.measles.packages)
        }:
            machine.succeed(f"runuser -l measles -c 'command -v {tool}'")
  '';
}
