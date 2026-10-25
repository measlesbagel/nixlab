{
  config,
  lib,
  pkgs,
  ...
}:
let
  node = config.homelab.nodes.${config.networking.hostName};
  # Single-use key from `nix run .#provision`, deleted after joining, so no
  # credential that can add devices stays on the host.
  authKeyFile = "/var/lib/nixlab/tailscale-authkey";
in
{
  services.tailscale = {
    enable = true;
    inherit authKeyFile;
    extraUpFlags = [
      "--ssh"
      "--accept-dns=true"
    ]
    ++ lib.optional (
      node.tailscaleTags != [ ]
    ) "--advertise-tags=${lib.concatStringsSep "," node.tailscaleTags}";
  };

  systemd.services.tailscaled-autoconnect = {
    unitConfig.ConditionPathExists = authKeyFile;
    serviceConfig.ExecStartPost = [ "${pkgs.coreutils}/bin/rm -f ${authKeyFile}" ];
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
}
