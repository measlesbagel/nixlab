{ config, inputs, ... }:
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
}
