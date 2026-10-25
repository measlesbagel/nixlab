# The join key never enters the image or the store: provision appends it as an
# initrd cpio at run time, and the initrd unit below moves it into /root.
{ lib, pkgs, ... }:
let
  stateDir = "/root/nixlab-installer";
in
{
  boot.initrd.systemd.services.nixlab-installer-state = {
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = "/sysroot";
      ConditionPathExists = "/nixlab-installer/authkey";
    };
    wantedBy = [ "initrd.target" ];
    before = [ "initrd-switch-root.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -m 700 -p /sysroot${stateDir}
      install -m 400 /nixlab-installer/* /sysroot${stateDir}/
    '';
  };

  # <host>-installer, so it never collides with the host's own node.
  systemd.services.nixlab-installer-hostname = {
    wantedBy = [ "multi-user.target" ];
    before = [ "tailscaled-autoconnect.service" ];
    unitConfig.ConditionPathExists = "${stateDir}/hostname";
    serviceConfig.Type = "oneshot";
    # tailscale reads the kernel hostname; hostnamectl --transient is ignored
    # while the image's static hostname is set.
    script = ''
      cat ${stateDir}/hostname > /proc/sys/kernel/hostname
    '';
  };

  services.tailscale = {
    enable = true;
    authKeyFile = "${stateDir}/authkey";
    extraUpFlags = [
      "--ssh"
      "--advertise-tags=tag:instar"
    ];
  };

  systemd.services.tailscaled-autoconnect = {
    unitConfig.ConditionPathExists = "${stateDir}/authkey";
    serviceConfig.ExecStartPost = [ "${pkgs.coreutils}/bin/rm -f ${stateDir}/authkey" ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # albipes's IT87 watchdog survives kexec; unfed, a long install resets the
  # box. Elsewhere the module just fails to load.
  boot.kernelModules = [ "it87_wdt" ];
  systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault "60s";
}
