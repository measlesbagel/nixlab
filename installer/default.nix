# Reached over the LAN at the host's own address: the kexec image keeps the
# old system's addresses, routes and root keys, which nixos-anywhere seeds.
{ lib, ... }:
{
  # albipes's IT87 watchdog survives kexec; unfed, a long install resets the
  # box. Elsewhere the module just fails to load.
  boot.kernelModules = [ "it87_wdt" ];
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault "60s";
}
