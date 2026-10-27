# Rolls back a switch nobody confirms (comin's hook in modules/comin.nix, or
# `nix run .#deploy`), and a never-proven boot that never becomes manageable
# (ssh + tailscale, not is-system-running).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "/var/lib/deploy-watchdog";
  runDir = "/run/deploy-watchdog";
  confirmWindow = 600;

  health = pkgs.writeShellApplication {
    name = "deploy-health";
    runtimeInputs = [
      pkgs.systemd
      pkgs.tailscale
      pkgs.jq
    ];
    text = ''
      systemctl is-active --quiet sshd.service
      systemctl is-active --quiet tailscaled.service
      tailscale status --json | jq -e '.BackendState == "Running"' > /dev/null
    '';
  };

  confirm = pkgs.writeShellApplication {
    name = "deploy-confirm";
    runtimeInputs = [
      pkgs.coreutils
      health
    ];
    text = ''
      deploy-health
      mkdir -p ${stateDir}
      readlink -f /run/current-system > ${stateDir}/confirmed
      # deploy-revert's target must survive garbage collection.
      ln -sfn "$(cat ${stateDir}/confirmed)" /nix/var/nix/gcroots/deploy-confirmed
      rm -f ${runDir}/pending

      # Else a power cut with the internet down rolls back a confirmed
      # userspace-only switch on its first boot.
      if [ "$(readlink -f /run/booted-system)" = "$(cat ${stateDir}/booted 2> /dev/null || true)" ] \
        && [ "$(readlink -f /run/booted-system/{initrd,kernel,kernel-modules})" \
          = "$(readlink -f /run/current-system/{initrd,kernel,kernel-modules})" ]; then
        readlink -f /run/current-system > ${stateDir}/booted
      fi

      echo "confirmed $(cat ${stateDir}/confirmed)"
    '';
  };

  # comin switches through its own profile (system-profiles/comin), so
  # `nixos-rebuild --rollback` would pick a stale system generation. Setting
  # the system profile also makes the target the default boot entry.
  revert = pkgs.writeShellApplication {
    name = "deploy-revert";
    runtimeInputs = [
      pkgs.coreutils
      config.nix.package
    ];
    text = ''
      target=$(cat ${stateDir}/confirmed 2> /dev/null || true)
      if [ -n "$target" ] && [ -x "$target/bin/switch-to-configuration" ] \
        && [ "$target" != "$(readlink -f /run/current-system)" ]; then
        echo "reverting to $target"
        nix-env --profile /nix/var/nix/profiles/system --set "$target"
        "$target/bin/switch-to-configuration" switch
      else
        /run/current-system/sw/bin/nixos-rebuild --rollback switch
      fi
    '';
  };

  rollback = pkgs.writeShellApplication {
    name = "deploy-rollback";
    runtimeInputs = [
      pkgs.coreutils
      revert
    ];
    text = ''
      deadline=$((SECONDS + ${toString confirmWindow}))
      while [ -e ${runDir}/pending ] && [ "$SECONDS" -lt "$deadline" ]; do
        sleep 5
      done

      if [ ! -e ${runDir}/pending ]; then
        exit 0
      fi

      echo "deploy not confirmed within ${toString confirmWindow}s — rolling back"
      rm -f ${runDir}/pending
      deploy-revert
    '';
  };

  bootGate = pkgs.writeShellApplication {
    name = "deploy-boot-gate";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      health
      confirm
      revert
    ];
    text = ''
      marker="${stateDir}/rolled-back-$(cat /proc/sys/kernel/random/boot_id)"
      booted=$(readlink -f /run/booted-system)

      for _ in 1 2 3 4 5 6; do
        if deploy-health 2> /dev/null; then
          deploy-confirm
          echo "$booted" > ${stateDir}/booted
          exit 0
        fi
        sleep 20
      done

      if [ "$booted" = "$(cat ${stateDir}/booted 2> /dev/null || true)" ]; then
        echo "host unmanageable, but this system has booted healthy before — not rolling back"
        exit 0
      fi

      if [ -f "$marker" ]; then
        exit 0
      fi

      echo "host unmanageable after boot — rolling back"
      touch "$marker"
      deploy-revert
      systemctl reboot
    '';
  };
in
{
  environment.systemPackages = [
    health
    confirm
  ];

  boot.loader.systemd-boot.bootCounting.enable = true;
  boot.kernelParams = [ "panic=30" ];

  # Live switches only: boot activation and fresh installs must never start a
  # countdown.
  system.activationScripts.deployWatchdogArm = {
    deps = [ "specialfs" ];
    text = ''
      if [ "''${NIXOS_ACTION:-}" = switch ] \
        && [ -f ${stateDir}/confirmed ] \
        && [ "$(cat ${stateDir}/confirmed)" != "$systemConfig" ]; then
        mkdir -p ${runDir}
        echo "$systemConfig" > ${runDir}/pending
      fi
    '';
  };

  systemd.paths.deploy-rollback = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathExists = "${runDir}/pending";
  };

  systemd.services.deploy-rollback = {
    description = "Roll back a deploy the deployer did not confirm";
    # Never restart mid-countdown when a deploy changes this unit.
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe rollback;
    };
  };

  systemd.services.deploy-watchdog = {
    description = "Boot health gate with automatic rollback";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    # Restarting it on switch would block the deploy.
    restartIfChanged = false;
    stopIfChanged = false;

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "deploy-watchdog";
      ExecStart = lib.getExe bootGate;
    };
  };
}
