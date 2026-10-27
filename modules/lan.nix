{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.homelab) wireguard nodes;
in
{
  options.homelab.lan.uplinkDrivers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Kernel drivers of the host's 10GbE uplinks.";
  };

  config = {
    # Jumbo frames on each host's 10GbE uplink. Only the first matching .link
    # file applies, and this one shadows 99-default.link, so it repeats its
    # policies.
    systemd.network.links = lib.listToAttrs (
      map (
        driver:
        lib.nameValuePair "10-uplink-${driver}" {
          matchConfig.Driver = driver;
          linkConfig = {
            MTUBytes = "9000";
            NamePolicy = "keep kernel database onboard slot path";
            AlternativeNamesPolicy = "database onboard slot path mac";
            MACAddressPolicy = "persistent";
          };
        }
      ) config.homelab.lan.uplinkDrivers
    );

    # Replies to WireGuard peers go back through the endpoint, not the router,
    # so the firewall can tell a peer's address from the endpoint's.
    systemd.services.wireguard-route = lib.mkIf (config.networking.hostName != wireguard.endpoint) {
      description = "Route the WireGuard subnet through its endpoint";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.iproute2 ];
      script = "ip route replace ${wireguard.subnet} via ${nodes.${wireguard.endpoint}.ip}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # The uplink may still be waiting for DHCP.
        Restart = "on-failure";
        RestartSec = 10;
      };
    };
  };
}
