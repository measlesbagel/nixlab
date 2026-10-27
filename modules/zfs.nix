{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (config.disko.devices) zpool;
  modes = lib.mapAttrs (_: pool: if lib.isString pool.mode then pool.mode else "") zpool;
  mounts = lib.concatMapAttrs (
    pool:
    { datasets, ... }:
    lib.mapAttrs' (name: dataset: lib.nameValuePair dataset.mountpoint "${pool}/${name}") (
      lib.filterAttrs (_: dataset: dataset.mountpoint or null != null) datasets
    )
  ) zpool;
in
{
  # The kexec installer's kernel pick. Not an exported module, so a moved file
  # fails eval.
  imports = [ "${inputs.nixos-images}/nix/latest-zfs-kernel.nix" ];

  boot.supportedFilesystems = [ "zfs" ];

  # Never force-import a pool another host may still own.
  boot.zfs.forceImportRoot = false;

  services.zfs = {
    autoScrub.enable = true;
    trim.enable = true;
  };

  # Resilvers and manual scrubs run outside any unit.
  homelab.reboot.busyWhen."a scrub or resilver" =
    "${config.boot.zfs.package}/bin/zpool status | grep 'in progress since' > /dev/null";

  # Each dataset that fileSystems mounts is `mountpoint=legacy` in its host's
  # disko.nix. A real path makes zfs-mount.service mount it too, racing the
  # mount unit on "dataset is busy". syncoid's replicas inherit legacy from
  # tank/backups, so they stay unmounted.
  disko.tests.extraChecks = ''
    with subtest("zfs-mount and the mount units did not race"):
        journal = machine.succeed("journalctl -b --no-pager -o cat")
        busy = [line for line in journal.splitlines() if "dataset is busy" in line or "zfs_mount_at() failed" in line]
        assert not busy, "\n".join(busy)

    with subtest("every pool imports with its layout, and every dataset is legacy and mounts where disko puts it"):
        for pool, mode in ${builtins.toJSON modes}.items():
            status = machine.succeed(f"zpool status {pool}")
            assert "state: ONLINE" in status, status
            assert mode in status, status
        for mountpoint, dataset in ${builtins.toJSON mounts}.items():
            machine.succeed(
                f'[ "$(findmnt -no SOURCE {mountpoint})" = {dataset} ]',
                f'[ "$(zfs get -H -o value mountpoint {dataset})" = legacy ]',
            )
  '';
}
