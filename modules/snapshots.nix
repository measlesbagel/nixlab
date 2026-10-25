{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.zfs;
in
{
  options.homelab.zfs.snapshots = mkOption {
    type = types.attrsOf (
      types.enum [
        "state"
        "bulk"
        "replica"
      ]
    );
    default = { };
    description = ''
      Dataset to policy class. `state` is irreplaceable service data; `bulk` is
      large, mostly append-only data where only deletions cost space; `replica`
      is a received copy, pruned here but never snapshotted (the source's
      snapshots arrive via replication). Nothing is kept beyond two weeks.
    '';
  };

  config.services.sanoid = lib.mkIf (cfg.snapshots != { }) {
    enable = true;

    # Every count explicit: sanoid's own defaults would exceed the two-week cap.
    templates =
      let
        twoWeeks = {
          frequently = 0;
          weekly = 0;
          monthly = 0;
          yearly = 0;
          autoprune = true;
        };
      in
      {
        state = twoWeeks // {
          hourly = 24;
          daily = 14;
          autosnap = true;
        };
        bulk = twoWeeks // {
          hourly = 0;
          daily = 7;
          autosnap = true;
        };
        # Must match `state`.
        replica = twoWeeks // {
          hourly = 24;
          daily = 14;
          autosnap = false;
        };
      };

    datasets = lib.mapAttrs (_: class: { useTemplate = [ class ]; }) cfg.snapshots;
  };
}
