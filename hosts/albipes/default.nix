{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "albipes";
  networking.hostId = "8425e349";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.zfs.snapshots = {
    "tank/objects" = "state";
    "tank/media" = "bulk";
  };
}
