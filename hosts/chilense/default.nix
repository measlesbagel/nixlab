# TODO(provisioning): GPU stack lands at migration.
{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "chilense";
  networking.hostId = "224a7262";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.zfs.snapshots."rpool/safe/home" = "state";
  homelab.zfs.replicate = [ "rpool/safe/home" ];

  hjem = {
    extraModules = [ inputs.hjem-rum.hjemModules.default ];
    users.measles = import ../../home/measles;
  };
}
