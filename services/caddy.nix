# One wildcard certificate via Cloudflare DNS-01, ordered by NixOS's ACME
# client (lego), so a vhost needs no public port and Caddy no DNS plugin.
{ config, lib, ... }:
let
  inherit (config.homelab) domain;
in
{
  # Every vhost serves the wildcard unless it names another certificate.
  options.services.caddy.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule { config.useACMEHost = lib.mkDefault domain; });
  };

  config = {
    services.caddy.enable = true;

    security.acme = {
      acceptTerms = true;
      certs.${domain} = {
        domain = "*.${domain}";
        dnsProvider = "cloudflare";
        credentialFiles.CLOUDFLARE_DNS_API_TOKEN_FILE = "/var/lib/opnix/secrets/cloudflareDnsToken";
      };
    };

    # Shared with ddns.nix: Zone:Zone:Read and Zone:DNS:Edit on this one zone.
    services.onepassword-secrets.secrets.cloudflareDnsToken = {
      reference = "op://homelab/cloudflare-dns-token/token";
      services = [ "acme-order-renew-${domain}" ];
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
