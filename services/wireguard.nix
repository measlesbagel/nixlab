# Remote access: the one WireGuard endpoint, with a router port forward to it.
# Lab hosts route the subnet back here (modules/lan.nix), so they see each
# peer's own address; anything else on the LAN sees this host.
{ config, lib, ... }:
let
  inherit (config.homelab) domain lan wireguard;
  prefix = lib.last (lib.splitString "/" wireguard.subnet);
  labIps = lib.mapAttrsToList (_: node: node.ip) config.homelab.nodes;
in
{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "${wireguard.address}/${prefix}" ];
    listenPort = wireguard.port;
    # Made on first boot and never leaves the host; commit the public half as
    # homelab.wireguard.publicKey.
    privateKeyFile = "/var/lib/wireguard/wg0.key";
    generatePrivateKeyFile = true;
    peers = lib.mapAttrsToList (_: peer: {
      inherit (peer) publicKey;
      allowedIPs = [ "${peer.ip}/32" ];
    }) wireguard.peers;
  };

  networking.firewall = {
    allowedUDPPorts = [ wireguard.port ];
    filterForward = true;
    extraForwardRules = ''
      iifname "wg0" ip daddr ${lan.subnet} accept
    '';
  };
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.nftables.tables.wireguard-nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        # On lo, masquerade swaps the host's own wg0 address for another interface's.
        ip saddr ${wireguard.subnet} ip daddr != { ${lib.concatStringsSep ", " labIps} } oifname != { "wg0", "lo" } masquerade
      }
    '';
  };

  # DNS-only, like the vhosts (services/ddns.nix).
  services.cloudflare-dyndns.domains = [ "vpn.${domain}" ];

  homelab.watchdog.healthChecks = [ "systemctl is-active --quiet wireguard-wg0.service" ];

  disko.tests.extraChecks = ''
    with subtest("wg0 listens on its port with the key the host made"):
        machine.wait_for_unit("wireguard-wg0.service")
        machine.succeed(
            '[ "$(wg show wg0 listen-port)" = ${toString wireguard.port} ]',
            '[ "$(stat -c %U:%a /var/lib/wireguard/wg0.key)" = root:600 ]',
            '[ "$(wg pubkey < /var/lib/wireguard/wg0.key)" = "$(wg show wg0 public-key)" ]',
        )

    with subtest("deploy-health fails while wg0 is down"):
        machine.succeed("systemctl stop wireguard-wg0.service")
        machine.fail("deploy-health")
        machine.succeed("systemctl start wireguard-wg0.service", "deploy-health")
  '';
}
