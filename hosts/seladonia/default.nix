{ inputs, lib, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "seladonia";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.snapshots = {
    "/mnt/btr_pool/@var-lib" = "state";
    "/mnt/btr_pool/@navidrome" = "state";
    "/mnt/btr_pool/@postgres" = "state";
  };

  homelab.replicate = [
    "/mnt/btr_pool/@navidrome"
    "/mnt/btr_pool/@postgres"
  ];

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
