# rpc.mountd exits if /var/lib/nfs/etab is missing when it starts. nfs-utils'
# `make install` creates the file, but nixpkgs installs into a scratch state
# dir, and nfs-server's `exportfs -r` only runs once mountd has forked.
{ config, lib, ... }:
{
  config = lib.mkIf config.services.nfs.server.enable {
    systemd.services.nfs-mountd.preStart = "touch /var/lib/nfs/etab";

    # rpc.mountd's parent exits 0 as its child dies, so nfs-mountd can end
    # inactive with Result=success while nfs-server stays up.
    disko.tests.extraChecks = ''
      with subtest("rpc.mountd runs behind the NFS server"):
          machine.succeed("systemctl is-active nfs-mountd.service", "pgrep -x rpc.mountd")
    '';
  };
}
