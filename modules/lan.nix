# Jumbo frames on each host's 10GbE uplink. Only the first matching .link file
# applies, and this one shadows 99-default.link, so it repeats its policies.
{ config, lib, ... }:
{
  options.homelab.lan.uplinkDrivers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Kernel drivers of the host's 10GbE uplinks.";
  };

  config.systemd.network.links = lib.listToAttrs (
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
}
