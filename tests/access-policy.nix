# Who may log in as whom from where, checked against each host's sshd AllowUsers (modules/ssh.nix). nftables
# opens port 22 to exactly these sources.
{
  lib,
  pkgs,
  nixosConfigurations,
}:
let
  inherit (lib)
    any
    concatMap
    filter
    head
    last
    splitString
    toInt
    ;

  hosts = lib.attrNames nixosConfigurations;
  inherit (nixosConfigurations.seladonia.config.homelab) nodes addressesOf;
  # A host name or a genus.
  hostsOf =
    dst:
    if nodes ? ${dst} then
      [ dst ]
    else
      lib.attrNames (lib.filterAttrs (_: node: node.genus == dst) nodes);

  toNumber = address: lib.foldl (acc: octet: acc * 256 + toInt octet) 0 (splitString "." address);
  inCidr =
    cidr: address:
    let
      parts = splitString "/" cidr;
      length = if lib.length parts == 2 then toInt (last parts) else 32;
      size = lib.foldl (acc: _: acc * 2) 1 (lib.range 1 (32 - length));
    in
    toNumber (head parts) / size == toNumber address / size;

  allowed =
    host: user: source:
    any (
      pattern:
      let
        parts = splitString "@" pattern;
      in
      head parts == user && inCidr (last parts) source
    ) nixosConfigurations.${host}.config.services.openssh.settings.AllowUsers;

  everyone = [
    "measles"
    "deploy"
    "syncoid"
    "root"
  ];

  # Sources and destinations are hosts, genera (docs/taxonomy.md) or, for
  # sources, addresses.
  cases = [
    {
      # A WireGuard peer.
      source = "10.100.0.2";
      dst = hosts;
      accept = [
        "measles"
        "deploy"
      ];
      deny = [
        "syncoid"
        "root"
      ];
    }
    {
      source = "homoeomma";
      dst = hosts;
      accept = [
        "measles"
        "deploy"
      ];
      deny = [
        "syncoid"
        "root"
      ];
    }
    {
      source = "hapalotremus";
      dst = [
        "typhochlaena"
        "homoeomma"
      ];
      accept = [ "syncoid" ];
      deny = [
        "measles"
        "deploy"
        "root"
      ];
    }
    {
      source = "hapalotremus";
      dst = [ "cyriocosmus" ];
      deny = everyone;
    }
    {
      # leetzi on the Sparks' direct link (modules/remote-builder.nix).
      source = "192.168.100.10";
      dst = [ "elegans" ];
      accept = [ "nix-builder" ];
      deny = everyone;
    }
    {
      # Includes WireGuard traffic the endpoint masquerades.
      source = "typhochlaena";
      dst = hosts;
      deny = everyone;
    }
    {
      source = "cyriocosmus";
      dst = hosts;
      deny = everyone;
    }
    {
      # Phones, IoT and guests on the LAN.
      source = "192.168.4.200";
      dst = hosts;
      deny = everyone;
    }
  ];

  failures = concatMap (
    c:
    concatMap (
      host:
      concatMap (
        address:
        map (user: "${user}@${host} from ${c.source} (${address}): should be accepted") (
          filter (user: !allowed host user address) (c.accept or [ ])
        )
        ++ map (user: "${user}@${host} from ${c.source} (${address}): should be denied") (
          filter (user: allowed host user address) (c.deny or [ ])
        )
      ) (addressesOf c.source)
    ) (concatMap hostsOf c.dst)
  ) cases;
in
assert lib.assertMsg (failures == [ ]) (lib.concatLines failures);
pkgs.runCommand "access-policy" { } "touch $out"
