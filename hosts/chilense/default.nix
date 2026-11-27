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
    ./peripherals.nix
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

    with subtest("the nushell Ghostty opens loads measles's config"):
        aliases = machine.succeed(
            "runuser -l measles -c '${lib.getExe config.hjem.users.measles.rum.programs.nushell.package} --config ~/.config/nushell/config.nu -c \"scope aliases | get name | to json -r\"' | tail -n 1"
        )
        assert set(${builtins.toJSON (lib.attrNames config.hjem.users.measles.rum.programs.nushell.aliases)}) <= set(json.loads(aliases)), aliases
  '';
}
