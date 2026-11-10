{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.snapshots;

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
        lib.recursiveUpdate acc { ${dirOf path}.subvolume.${baseNameOf path} = { }; }
      else
        acc
    ) { } cfg;
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
      `@snapshots`. `state` is irreplaceable service data; `bulk` is large,
      mostly append-only data where only deletions cost space. Nothing is kept
      beyond two weeks.
    '';
  };

  config.services.btrbk.instances = lib.mapAttrs (class: c: {
    inherit (c) onCalendar;
    settings = {
      timestamp_format = "long";
      snapshot_dir = "@snapshots";
      snapshot_preserve_min = "latest";
      snapshot_preserve = c.preserve;
      volume = volumesOf class;
    };
  }) (lib.filterAttrs (class: _: volumesOf class != { }) classes);
}
