# Source side of albipes's syncoid pulls, over the LAN with albipes's own key.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.homelab.zfs) pullKey;
  datasets = config.homelab.zfs.replicate;
  albipes = config.homelab.nodes.albipes.ip;
in
{
  options.homelab.zfs = {
    replicate = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Datasets pulled by albipes; keep secrets out of these.";
    };
    pullKey = mkOption {
      type = types.nullOr types.str;
      # Set once albipes has made it (docs/remote-access.md).
      default = null;
      description = "albipes's syncoid public key, /var/lib/syncoid/.ssh/id_ed25519.pub.";
    };
  };

  config = lib.mkIf (datasets != [ ]) {
    users.users.syncoid = {
      isSystemUser = true;
      group = "syncoid";
      home = "/var/lib/syncoid";
      useDefaultShell = true;
      openssh.authorizedKeys.keys = lib.optional (
        pullKey != null
      ) ''from="${albipes}",restrict ${pullKey}'';
    };
    users.groups.syncoid = { };

    homelab.ssh.logins.syncoid = [ "hapalotremus" ];

    # --no-sync-snap pulls need only send and hold.
    systemd.services.zfs-replication-delegate = {
      description = "Delegate ZFS send rights to syncoid";
      wantedBy = [ "multi-user.target" ];
      after = [ "zfs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = lib.concatMapStringsSep "\n" (
        d: "/run/booted-system/sw/bin/zfs allow syncoid send,hold ${d}"
      ) datasets;
    };

    disko.tests.extraChecks = ''
      with subtest("syncoid may send and hold each replicated dataset"):
          machine.wait_for_unit("zfs-replication-delegate.service")
          for dataset in ${builtins.toJSON datasets}:
              machine.succeed(f"zfs allow {dataset} | grep 'user syncoid hold,send'")
    '';
  };
}
