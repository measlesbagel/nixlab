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

  # disko sets each dataset's mountpoint property and also mounts it through
  # fileSystems, so `zfs mount -a` races those mounts and fails on "dataset is
  # busy". Undeclared datasets, such as syncoid's replicas, stay unmounted.
  systemd.services.zfs-mount.enable = false;

  # Resilvers and manual scrubs run outside any unit.
  homelab.reboot.busyWhen."a scrub or resilver" =
    "${config.boot.zfs.package}/bin/zpool status | grep 'in progress since' > /dev/null";

  disko.tests.extraChecks = ''
    with subtest("every pool imports with its layout, and every dataset mounts where disko puts it"):
        for pool, mode in ${builtins.toJSON modes}.items():
            status = machine.succeed(f"zpool status {pool}")
            assert "state: ONLINE" in status, status
            assert mode in status, status
        for mountpoint, dataset in ${builtins.toJSON mounts}.items():
            machine.succeed(f'[ "$(findmnt -no SOURCE {mountpoint})" = {dataset} ]')
  '';
}
