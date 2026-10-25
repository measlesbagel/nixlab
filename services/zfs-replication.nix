{
  config,
  inputs,
  lib,
  ...
}:
let
  sources = [
    "seladonia"
    "chilense"
  ];

  replicas = lib.concatMap (
    host:
    map (dataset: {
      inherit host dataset;
      target = "tank/backups/${host}-${baseNameOf dataset}";
    }) inputs.self.nixosConfigurations.${host}.config.homelab.zfs.replicate
  ) sources;
in
{
  services.syncoid = {
    enable = true;
    commonArgs = [
      "--no-sync-snap"
      "--sshoption=StrictHostKeyChecking=accept-new"
    ];
    commands = lib.listToAttrs (
      map (
        r:
        lib.nameValuePair "${r.host}-${baseNameOf r.dataset}" {
          source = "syncoid@${config.homelab.nodes.${r.host}.tailscaleName}:${r.dataset}";
          inherit (r) target;
          recvOptions = "u";
        }
      ) replicas
    );
  };

  homelab.zfs.snapshots = lib.listToAttrs (map (r: lib.nameValuePair r.target "replica") replicas);

  homelab.reboot.blockers = [ "syncoid-*.service" ];
}
