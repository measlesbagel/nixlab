{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.homelab.backup.paths = mkOption {
    type = types.listOf types.str;
    default = [ ];
  };

  config = lib.mkIf (config.homelab.backup.paths != [ ]) {
    services.onepassword-secrets.secrets = {
      rustfsResticEnv = {
        reference = "op://homelab/rustfs-restic-env/env";
        services = [ "restic-backups-nas" ];
      };
      resticPassword = {
        reference = "op://homelab/restic-password/password";
        services = [ "restic-backups-nas" ];
      };
    };

    services.restic.backups.nas = {
      inherit (config.homelab.backup) paths;
      initialize = true;
      repository = "s3:http://${config.homelab.nodes.albipes.ip}:9000/restic-${config.networking.hostName}";
      environmentFile = "/var/lib/opnix/secrets/rustfsResticEnv";
      passwordFile = "/var/lib/opnix/secrets/resticPassword";
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
      # Matches the two-week snapshot cap (modules/snapshots.nix).
      pruneOpts = [ "--keep-daily 14" ];
    };

    homelab.reboot.blockers = [ "restic-backups-nas.service" ];
  };
}
