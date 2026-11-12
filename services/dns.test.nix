# Boot-test check of dns.nix (modules/vm-test.nix). The host's own queries
# never cross wg0, so a peer in a network namespace asks through a real
# tunnel. The VM has no LAN, so the host's LAN address goes on lo to ask from.
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

  dig = lib.getExe' pkgs.dnsutils "dig";
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
  homelab.vmTest.checks.dns = ''
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
