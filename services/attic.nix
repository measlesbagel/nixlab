{ config, lib, ... }:
let
  storage = "/tank/nix-cache";
in
{
  services.atticd = {
    enable = true;
    environmentFile = "/var/lib/opnix/secrets/atticServerEnv";
    settings = {
      listen = "[::]:${toString config.homelab.cache.port}";
      api-endpoint = "http://${config.homelab.nodes.albipes.tailscaleName}:${toString config.homelab.cache.port}/";
      storage = {
        type = "local";
        path = storage;
      };
      # Matches the lab-wide two-week retention (modules/snapshots.nix).
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "14 days";
      };
    };
  };

  # A DynamicUser cannot own a dataset mounted outside its StateDirectory.
  users.users.atticd = {
    isSystemUser = true;
    group = "atticd";
  };
  users.groups.atticd = { };
  systemd.services.atticd = {
    serviceConfig.DynamicUser = lib.mkForce false;
    unitConfig.RequiresMountsFor = [ storage ];
  };
  systemd.tmpfiles.rules = [ "d ${storage} 0750 atticd atticd -" ];

  # 1Password item: a field holding
  # `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 RSA PKCS1 PEM>`, the
  # token-signing key (not the NAR signing key, which atticd generates).
  services.onepassword-secrets.secrets.atticServerEnv = {
    reference = "op://homelab/attic-server-env/env";
    services = [ "atticd" ];
  };

  # Hosts pull over the LAN; CI pushes over the tailnet (trusted interface).
  networking.firewall.allowedTCPPorts = [ config.homelab.cache.port ];
}
