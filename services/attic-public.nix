# The lab cache's read-only public face, so CI can substitute what the hosts
# built. Reads are public anyway (`cache create --public`); everything else,
# the token API included, stays LAN-only on albipes.
{ config, ... }:
let
  inherit (config.homelab) cache nodes;
in
{
  services.caddy.virtualHosts."cache.${config.homelab.domain}".extraConfig = ''
    @read {
      method GET HEAD
      path /${cache.name}/*
    }
    handle @read {
      request_header -Authorization
      reverse_proxy ${nodes.albipes.ip}:${toString cache.port}
    }
    respond 403
  '';
}
