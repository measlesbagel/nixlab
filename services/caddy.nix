# Certificates via Cloudflare DNS-01, so a vhost needs no public port.
{ pkgs, ... }:
{
  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
    };
    environmentFile = "/var/lib/opnix/secrets/caddyCloudflareEnv";
    globalConfig = ''
      acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    '';
  };

  # 1Password item: a field holding `CLOUDFLARE_API_TOKEN=<token>`, where the
  # token has Zone:Zone:Read and Zone:DNS:Edit on this one zone.
  services.onepassword-secrets.secrets.caddyCloudflareEnv = {
    reference = "op://homelab/caddy-cloudflare-env/env";
    services = [ "caddy" ];
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
