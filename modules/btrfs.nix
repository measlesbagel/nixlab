{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Started by hand, these run outside any unit.
  maintenanceRunning = pkgs.writeShellScript "btrfs-maintenance-running" ''
    PATH=${
      lib.makeBinPath [
        pkgs.btrfs-progs
        pkgs.util-linux
        pkgs.gnugrep
      ]
    }
    for fs in $(findmnt -rn -t btrfs -o TARGET); do
      btrfs scrub status "$fs" 2> /dev/null | grep -q 'Status: *running' && exit 0
      btrfs balance status "$fs" 2> /dev/null | grep -q 'is running' && exit 0
      btrfs replace status -1 "$fs" 2> /dev/null | grep -q '% done' && exit 0
    done
    exit 1
  '';

  filesystems = lib.filter (content: (content.type or null) == "btrfs") (
    lib.concatMap (
      disk: lib.mapAttrsToList (_: partition: partition.content) (disk.content.partitions or { })
    ) (lib.attrValues config.disko.devices.disk)
  );
  # Mountpoint to the path inside its filesystem that must be mounted there.
  mounts = lib.listToAttrs (
    lib.concatMap (
      fs:
      lib.optional (fs.mountpoint != null) (lib.nameValuePair fs.mountpoint "/")
      ++ lib.concatMap (
        subvolume:
        lib.optional (subvolume.mountpoint != null) (
          lib.nameValuePair subvolume.mountpoint "/${lib.removePrefix "/" subvolume.name}"
        )
      ) (lib.attrValues fs.subvolumes)
    ) filesystems
  );
in
{
  services.btrfs.autoScrub.enable = true;

  homelab.reboot.busyWhen."a scrub, balance or device replace" = "${maintenanceRunning}";
  homelab.reboot.blockers = [ "btrbk-*.service" ];

  homelab.vmTest.checks.btrfs = ''
    with subtest("every mountpoint in the disko layout holds its btrfs subvolume"):
        machine.succeed(*${
          builtins.toJSON (
            lib.mapAttrsToList (
              mountpoint: root:
              ''[ "$(findmnt -rno FSTYPE,FSROOT --mountpoint ${mountpoint})" = "btrfs ${root}" ]''
            ) mounts
          )
        })
  '';
}
