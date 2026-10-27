# Reboots into a deployed kernel, initrd or module set in the host's hour of the
# night, once the deploy is confirmed and no registered blocker is busy.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.reboot;
  inherit (config.homelab.nodes.${config.networking.hostName}) roles;

  check = pkgs.writeShellApplication {
    name = "reboot-when-safe";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      booted=$(readlink -f /run/booted-system/{initrd,kernel,kernel-modules})
      deployed=$(readlink -f /run/current-system/{initrd,kernel,kernel-modules})
      if [ "$booted" = "$deployed" ]; then
        exit 0
      fi

      if [ -e /run/deploy-watchdog/pending ] \
        || [ "$(readlink -f /run/current-system)" != "$(cat /var/lib/deploy-watchdog/confirmed 2> /dev/null || true)" ]; then
        echo "reboot pending: the deployed system is not confirmed yet"
        exit 0
      fi

      ${lib.optionalString (cfg.blockers != [ ]) ''
        # A unit waiting out RestartSec shows as activating; one that keeps
        # failing must not hold reboots off forever.
        busy=$(systemctl list-units --plain --no-legend \
          --state=active,activating,deactivating,reloading \
          ${lib.escapeShellArgs cfg.blockers} \
          | awk '$4 != "auto-restart" { print $1 }' | paste -sd' ')
        if [ -n "$busy" ]; then
          echo "reboot pending: waiting for $busy"
          exit 0
        fi
      ''}

      ${lib.concatStrings (
        lib.mapAttrsToList (name: condition: ''
          if ${condition}; then
            echo ${lib.escapeShellArg "reboot pending: waiting for ${name}"}
            exit 0
          fi
        '') cfg.busyWhen
      )}

      ${lib.optionalString cfg.whenLoggedOut ''
        # deploy's sessions are automation.
        users=$(loginctl list-sessions --json=short \
          | jq -r '[.[] | select(.class == "user" and .user != "deploy") | .user] | unique | join(" ")')
        if [ -n "$users" ]; then
          echo "reboot pending: waiting for $users to log out"
          exit 0
        fi
      ''}

      echo "rebooting into the deployed kernel"
      systemctl reboot
    '';
  };
in
{
  options.homelab.reboot = {
    hour = mkOption {
      type = types.ints.between 0 23;
      # Storage reboots an hour before the hosts that use it.
      default = if lib.elem "storage" roles then 4 else 5;
      description = "Hour of the night in which the host may reboot itself.";
    };
    whenLoggedOut = mkOption {
      type = types.bool;
      default = lib.elem "desktop" roles;
      description = "Reboot only while nobody is logged in.";
    };
    blockers = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Unit name patterns that hold off a reboot while they run.";
    };
    busyWhen = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Shell conditions, by what they wait for, that hold off a reboot while they succeed.";
    };
  };

  config = {
    systemd.services.reboot-when-safe = {
      description = "Reboot into a deployed kernel once the host is idle";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe check;
      };
    };

    systemd.timers.reboot-when-safe = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = "*-*-* ${lib.fixedWidthNumber 2 cfg.hour}:00/15";
    };
  };
}
