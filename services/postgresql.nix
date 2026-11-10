{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) attrNames mkOption types;
in
{
  options.homelab.postgres.databases = mkOption {
    type = types.attrsOf (types.submodule { });
    default = { };
  };

  config = {
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_18;
      ensureDatabases = attrNames config.homelab.postgres.databases;
      ensureUsers = map (name: {
        inherit name;
        ensureDBOwnership = true;
      }) (attrNames config.homelab.postgres.databases);
    };

    services.postgresqlBackup = {
      enable = true;
      # Must finish before the 03:00 restic run in modules/backup.nix.
      startAt = "*-*-* 01:15:00";
      location = "/var/backup/postgresql";
      backupAll = true;
    };

    homelab.backup.paths = [ "/var/backup/postgresql" ];
    homelab.reboot.blockers = [ "postgresqlBackup.service" ];

    # Only keeps a late or manual dump from overlapping an upload; the timers
    # fire independently.
    systemd.services.restic-backups-nas.after = [ "postgresqlBackup.service" ];
  };
}
