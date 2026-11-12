{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.snapshots;
  inherit (config.homelab) replicate replication;

  # btrbk keeps hourlies for 24h and dailies for the given span.
  classes = {
    state = {
      onCalendar = "hourly";
      preserve = "24h 14d";
    };
    bulk = {
      onCalendar = "daily";
      preserve = "7d";
    };
  };

  volumesOf =
    class:
    lib.foldlAttrs (
      acc: path: c:
      if c == class then
        lib.recursiveUpdate acc {
          ${dirOf path}.subvolume.${baseNameOf path} = lib.optionalAttrs (lib.elem path replicate) {
            snapshot_dir = replication.snapshotDir;
          };
        }
      else
        acc
    ) { } cfg;
  active = lib.filterAttrs (class: _: volumesOf class != { }) classes;

  snapshotDirOf =
    path: "${dirOf path}/${if lib.elem path replicate then replication.snapshotDir else "@snapshots"}";
in
{
  options.homelab.snapshots = mkOption {
    type = types.attrsOf (
      types.enum [
        "state"
        "bulk"
      ]
    );
    default = { };
    example = {
      "/mnt/btr_pool/@home" = "state";
    };
    description = ''
      btrfs subvolume to policy class, each given as its path under the
      filesystem's top-level mount; snapshots land in that mount's
      `@snapshots`, those of `homelab.replicate` in a directory of their own
      (modules/replication.nix). `state` is irreplaceable service data; `bulk` is large,
      mostly append-only data where only deletions cost space. Nothing is kept
      beyond two weeks.
    '';
  };

  config = {
    services.btrbk.instances = lib.mapAttrs (class: c: {
      inherit (c) onCalendar;
      settings = {
        timestamp_format = "long";
        snapshot_dir = "@snapshots";
        snapshot_preserve_min = "latest";
        snapshot_preserve = c.preserve;
        volume = volumesOf class;
      };
    }) active;

    # A snapshot is <subvolume>.<timestamp>. The directories must match
    # exactly: what albipes may read is decided by directory
    # (modules/replication.nix).
    homelab.vmTest.checks.snapshots = lib.mkIf (cfg != { }) ''
      with subtest("btrbk snapshots each listed subvolume into its directory"):
          machine.succeed("systemctl start ${
            toString (map (class: "btrbk-${class}.service") (lib.attrNames active))
          }")
          snapshot_dirs: dict[str, list[str]] = ${
            builtins.toJSON (lib.mapAttrs (_: map baseNameOf) (lib.groupBy snapshotDirOf (lib.attrNames cfg)))
          }
          for directory, subvolumes in snapshot_dirs.items():
              found = machine.succeed(f"ls {quote(directory)}").split()
              snapshotted = {name.rsplit(".", 1)[0] for name in found if "." in name}
              assert snapshotted == set(subvolumes), f"{directory} holds {found}"
    '';
  };
}
