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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
