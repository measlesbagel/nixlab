# Source side of albipes's pulls over Tailscale SSH; the tailnet ACL must
# allow albipes -> syncoid@<host>.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  datasets = config.homelab.zfs.replicate;
in
{
  options.homelab.zfs.replicate = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "Datasets pulled by albipes; keep secrets out of these.";
  };

  config = lib.mkIf (datasets != [ ]) {
    users.users.syncoid = {
      isSystemUser = true;
      group = "syncoid";
      home = "/var/lib/syncoid";
      useDefaultShell = true;
    };
    users.groups.syncoid = { };

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
  };
}
