{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  sources = [
    "seladonia"
    "chilense"
  ];
  sshKey = "/var/lib/btrbk/.ssh/id_ed25519";
  backups = "/tank/backups";

  volumes = lib.foldl' lib.recursiveUpdate { } (
    lib.concatMap (
      host:
      let
        inherit (inputs.self.nixosConfigurations.${host}.config.homelab) replicate replication;
      in
      map (path: {
        "ssh://${host}${dirOf path}".subvolume.${baseNameOf path} = {
          snapshot_dir = replication.snapshotDir;
          target = "${backups}/${host}";
        };
      }) replicate
    ) sources
  );
in
{
  services.btrbk.instances.replication = {
    # After the sources' hourly snapshots, which may start up to 10 minutes
    # late (AccuracySec in the btrbk module).
    onCalendar = "*:20";
    settings = {
      ssh_identity = sshKey;
      ssh_user = "btrbk";
      timestamp_format = "long";
      # The sources snapshot and prune on their own (modules/snapshots.nix).
      snapshot_create = "no";
      snapshot_preserve_min = "all";
      # Must match the `state` class.
      target_preserve_min = "latest";
      target_preserve = "24h 14d";
      volume = volumes;
    };
  };

  systemd.tmpfiles.rules = map (host: "d ${backups}/${host} 0750 root root") sources;

  # Made here and never copied anywhere; only its public half is committed.
  # Named off btrbk-* so it never counts as a reboot blocker.
  systemd.services.ssh-keygen-btrbk = {
    description = "Create btrbk's SSH key";
    path = [ pkgs.openssh ];
    script = ''
      if [ ! -e ${sshKey} ]; then
        mkdir -p -m 700 "$(dirname ${sshKey})"
        ssh-keygen -q -t ed25519 -N "" -C btrbk@albipes -f ${sshKey}
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "btrbk";
      Group = "btrbk";
      StateDirectory = "btrbk";
    };
  };

  systemd.services.btrbk-replication = {
    requires = [ "ssh-keygen-btrbk.service" ];
    after = [ "ssh-keygen-btrbk.service" ];
    # tank is nofail (hosts/albipes/disko.nix); without it this would receive
    # onto the OS disk.
    unitConfig.RequiresMountsFor = [ backups ];
  };
}
