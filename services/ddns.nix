# DNS-only records (not proxied), matching the router's port forwards.
{ config, lib, ... }:
{
  services.cloudflare-dyndns = {
    enable = true;
    apiTokenFile = "/var/lib/opnix/secrets/cloudflareDnsToken";
    domains = lib.attrNames config.services.caddy.virtualHosts;
  };

  # Shared with caddy.nix: Zone:Zone:Read and Zone:DNS:Edit on this one zone.
  services.onepassword-secrets.secrets.cloudflareDnsToken = {
    reference = "op://homelab/cloudflare-dns-token/token";
    services = [ "cloudflare-dyndns" ];
  };
}
