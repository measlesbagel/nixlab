# Names for WireGuard peers: every host as <name>.lab.<domain>, and
# id.<domain> at its LAN address. Peers set it as their DNS server; anything
# else it resolves itself.
{ config, lib, ... }:
let
  inherit (config.homelab)
    domain
    lan
    wireguard
    nodes
    ;
in
{
  services.unbound = {
    enable = true;
    # Peers only; the host keeps the router's resolver.
    resolveLocalQueries = false;
    settings.server = {
      interface = [ wireguard.address ];
      # wg0 may come up after unbound.
      ip-freebind = true;
      access-control = [ "${wireguard.subnet} allow" ];
      local-zone = [ ''"${lan.domain}." static'' ];
      local-data = lib.mapAttrsToList (name: node: ''"${name}.${lan.domain}. A ${node.ip}"'') nodes ++ [
        ''"id.${domain}. A ${nodes.seladonia.ip}"''
      ];
    };
  };

  homelab.watchdog.healthChecks = [ "systemctl is-active --quiet unbound.service" ];
}
