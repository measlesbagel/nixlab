{
  config,
  inputs,
  lib,
  ...
}:
let
  root = "/tank/media/music";

  clients = lib.filter (
    name: inputs.self.nixosConfigurations.${name}.config.services.navidrome.enable
  ) (lib.attrNames inputs.self.nixosConfigurations);
in
{
  # Files must be world-readable: the export squashes root and navidrome's
  # uid differs between hosts.
  systemd.tmpfiles.rules = [ "d ${root} 0755 root root -" ];

  services.nfs.server = {
    enable = true;
    exports = lib.concatMapStrings (
      name: "${root} ${config.homelab.nodes.${name}.ip}(ro,no_subtree_check,root_squash)\n"
    ) clients;
  };
  services.nfs.settings.nfsd = {
    vers3 = false;
    "vers4.0" = false;
  };
  networking.firewall.allowedTCPPorts = [ 2049 ];
}
