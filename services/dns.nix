# Names for WireGuard peers: every host as <name>.lab.<domain>, and
# id.<domain> at its LAN address. Peers set it as their DNS server; anything
# else it resolves itself.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.homelab)
    domain
    lan
    wireguard
    nodes
    ;
  dig = "${pkgs.dnsutils}/bin/dig";
  lanIp = nodes.${config.networking.hostName}.ip;
  testPeer = pkgs.writeShellApplication {
    name = "wg-test-peer";
    runtimeInputs = [
      pkgs.gawk
      pkgs.iproute2
      pkgs.wireguard-tools
    ];
    text = builtins.readFile ../scripts/wg-test-peer.sh;
  };
  peerIp = lib.concatStringsSep "." (lib.init (lib.splitString "." wireguard.address) ++ [ "254" ]);
  # What a peer should get back.
  lookups = lib.concatLines (
    lib.mapAttrsToList
      (name: ip: ''[ "$(ip netns exec peer ${dig} +short @${wireguard.address} ${name})" = ${ip} ]'')
      (
        lib.mapAttrs' (name: node: lib.nameValuePair "${name}.${lan.domain}" node.ip) nodes
        // {
          "id.${domain}" = nodes.seladonia.ip;
        }
      )
  );
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

  # The host's own queries leave through lo, where wireguard-nat rewrites a
  # subnet source to whichever interface registered first, so a peer in a
  # network namespace asks instead. The VM has no LAN, so the host's LAN
  # address goes on lo to ask from.
  disko.tests.extraChecks = ''
    from datetime import timedelta

    with subtest("unbound answers lab names to a WireGuard peer and refuses the LAN"):
        machine.succeed("${lib.getExe testPeer} ${peerIp}")
        machine.wait_until_succeeds(${builtins.toJSON lookups}, timeout=timedelta(minutes=1))
        machine.succeed(
            "ip addr add ${lanIp}/32 dev lo",
            "${dig} -b ${lanIp} @${wireguard.address} ${config.networking.hostName}.${lan.domain} | grep 'status: REFUSED'",
            "ip addr del ${lanIp}/32 dev lo",
        )

    with subtest("deploy-health fails while unbound is down"):
        machine.succeed("systemctl stop unbound.service")
        machine.fail("deploy-health")
        machine.succeed("systemctl start unbound.service", "deploy-health")
  '';
}
