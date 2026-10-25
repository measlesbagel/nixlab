{ inputs, lib, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "seladonia";
  networking.hostId = "9242acfc";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.zfs.snapshots = {
    "rpool/safe/var-lib" = "state";
    "rpool/safe/navidrome" = "state";
    "rpool/safe/postgres" = "state";
  };

  homelab.zfs.replicate = [
    "rpool/safe/navidrome"
    "rpool/safe/postgres"
  ];

  # Leave RAM for postgres and services; ARC otherwise takes up to half.
  boot.kernelParams = [ "zfs.zfs_arc_max=${toString (8 * 1024 * 1024 * 1024)}" ];

  virtualisation.vmVariant = {
    users.users.root.initialPassword = "vm";
    users.users.measles = {
      isNormalUser = true;
      initialPassword = "vm";
    };
    # Keep the VM interactive; the watchdog would reboot-loop on degraded boot.
    systemd.services.deploy-watchdog.wantedBy = lib.mkForce [ ];
    systemd.paths.deploy-rollback.wantedBy = lib.mkForce [ ];
  };
}
