# rpc.mountd exits if /var/lib/nfs/etab is missing when it starts. nfs-utils'
# `make install` creates the file, but nixpkgs installs into a scratch state
# dir, and nfs-server's `exportfs -r` only runs once mountd has forked.
{ config, lib, ... }:
{
  config = lib.mkIf config.services.nfs.server.enable {
    systemd.services.nfs-mountd.preStart = "touch /var/lib/nfs/etab";
  };
}
