# TODO(provisioning): GPU stack lands at migration.
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
  networking.hostId = "224a7262";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.zfs.snapshots."rpool/safe/home" = "state";
  homelab.zfs.replicate = [ "rpool/safe/home" ];

  hjem = {
    extraModules = [ inputs.hjem-rum.hjemModules.default ];
    users.measles = import ../../home/measles;
  };

  disko.tests.extraChecks = ''
    with subtest("measles logs in to his hjem packages on PATH"):
        machine.succeed("runuser -l measles -c 'command -v ${
          toString (map (p: baseNameOf (lib.getExe p)) config.hjem.users.measles.packages)
        }'")
  '';
}
