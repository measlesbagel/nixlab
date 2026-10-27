{
  config,
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
  sshKey = "/var/lib/syncoid/.ssh/id_ed25519";

  replicas = lib.concatMap (
    host:
    map (dataset: {
      inherit host dataset;
      target = "tank/backups/${host}-${baseNameOf dataset}";
    }) inputs.self.nixosConfigurations.${host}.config.homelab.zfs.replicate
  ) sources;

  # modules/replication.nix: the sources accept the key once it is committed.
  address =
    host:
    if config.homelab.zfs.pullKey != null then
      config.homelab.nodes.${host}.ip
    else
      config.homelab.nodes.${host}.tailscaleName;
in
{
  services.syncoid = {
    enable = true;
    inherit sshKey;
    commonArgs = [
      "--no-sync-snap"
      "--sshoption=StrictHostKeyChecking=accept-new"
    ];
    commands = lib.listToAttrs (
      map (
        r:
        lib.nameValuePair "${r.host}-${baseNameOf r.dataset}" {
          source = "syncoid@${address r.host}:${r.dataset}";
          inherit (r) target;
          recvOptions = "u";
          service = {
            requires = [ "ssh-keygen-syncoid.service" ];
            after = [ "ssh-keygen-syncoid.service" ];
          };
        }
      ) replicas
    );
  };

  # Made here and never copied anywhere; only its public half is committed.
  # Named off syncoid-* so it never counts as a reboot blocker.
  systemd.services.ssh-keygen-syncoid = {
    description = "Create syncoid's SSH key";
    path = [ pkgs.openssh ];
    script = ''
      if [ ! -e ${sshKey} ]; then
        mkdir -p -m 700 "$(dirname ${sshKey})"
        ssh-keygen -q -t ed25519 -N "" -C syncoid@albipes -f ${sshKey}
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "syncoid";
      Group = "syncoid";
      StateDirectory = "syncoid";
      StateDirectoryMode = "700";
    };
  };

  homelab.zfs.snapshots = lib.listToAttrs (map (r: lib.nameValuePair r.target "replica") replicas);

  homelab.reboot.blockers = [ "syncoid-*.service" ];
}
