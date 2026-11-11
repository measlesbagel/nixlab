{ lib, pkgs, ... }:
let
  # Started by hand, these run outside any unit.
  maintenanceRunning = pkgs.writeShellScript "btrfs-maintenance-running" ''
    PATH=${
      lib.makeBinPath [
        pkgs.btrfs-progs
        pkgs.util-linux
        pkgs.gnugrep
      ]
    }
    for fs in $(findmnt -rn -t btrfs -o TARGET); do
      btrfs scrub status "$fs" 2> /dev/null | grep -q 'Status: *running' && exit 0
      btrfs balance status "$fs" 2> /dev/null | grep -q 'is running' && exit 0
      btrfs replace status -1 "$fs" 2> /dev/null | grep -q '% done' && exit 0
    done
    exit 1
  '';
in
{
  services.btrfs.autoScrub.enable = true;

  homelab.reboot.busyWhen."a scrub, balance or device replace" = "${maintenanceRunning}";
  homelab.reboot.blockers = [ "btrbk-*.service" ];
}
