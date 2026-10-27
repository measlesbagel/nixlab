# WireGuard DNS

seladonia is the WireGuard endpoint. It makes its own `wg0` key on first boot
and serves unbound on `10.100.0.1` to peers. unbound answers every lab host as
`<name>.lab.measlesbagel.dev`, and `id.measlesbagel.dev` at seladonia's LAN
address.

## Sub-features

- `wg-key`: `wg0` is up on `10.100.0.1/24`, listening on 51820, with a private key generated on the host.
- `dns-lab-names`: every host in `modules/topology.nix` resolves to its LAN IP.
- `dns-id`: `id.measlesbagel.dev` resolves to seladonia's IP.
- `dns-scope`: unbound does not listen on the LAN address.

## How to get to it (user POV)

- A WireGuard peer sets `10.100.0.1` as its DNS server and looks up
  `albipes.lab.measlesbagel.dev`.
- On the host, `wg show wg0 public-key` gives the key to commit as
  `homelab.wireguard.publicKey`.

## Driving it with nixlab-vm

Preconditions:

- The baseline is met.

Steps:

- **Interface.** Run `nixlab-vm exec -- 'ip -br addr show wg0; wg show wg0 listen-port; ls -l /var/lib/wireguard/wg0.key'`.
  The output shows `10.100.0.1/24`, `51820`, and `/var/lib/wireguard/wg0.key` with mode `-rw-------`, owned by root.
- **A resolver.** The VM has no network, so `nix shell` cannot fetch `dig`.
  Build it on this machine with
  `nix build --no-link --print-out-paths --inputs-from . 'nixpkgs#dnsutils^dnsutils'`,
  and use `<path>/bin/dig` in the VM, which sees the host store. Call it `$DIG`
  below.
- **Lab names, as a peer.** Run `nixlab-vm exec -- 'ip addr add 10.100.0.9/32 dev lo; for h in seladonia albipes chilense leetzi elegans; do echo "$h $($DIG -b 10.100.0.9 +short @10.100.0.1 $h.lab.measlesbagel.dev)"; done; echo "id $($DIG -b 10.100.0.9 +short @10.100.0.1 id.measlesbagel.dev)"; ip addr del 10.100.0.9/32 dev lo'`.
  The output is `seladonia 192.168.4.39`, `albipes 192.168.4.41`, `chilense 192.168.4.21`, `leetzi 192.168.4.51`, `elegans 192.168.4.50` and `id 192.168.4.39`.
- **Peers only.** Run the same dig with `-b 10.0.2.15`, the VM's non-WireGuard address. `status: REFUSED`.
- **Not on the LAN.** Run `nixlab-vm exec -- 'ss -lunp | grep unbound'`. The only socket is
  `10.100.0.1:53`.

## Gotchas

- Always pass `-b` with an address in `10.100.0.0/24` (10.100.0.9 on `lo`
  stands in for a peer). Without it, the source can be `10.0.2.15`, which is
  correctly REFUSED. The VM's `host` command has no `-b`, so use `dig`.
- One early run got REFUSED for `-b 10.100.0.1`, and three repeats gave
  NOERROR. Use 10.100.0.9 as the source, and if one lookup is REFUSED,
  repeat it before calling it a regression.
- No peers are configured on `main`, so a real handshake cannot be proven.
- The public key changes on every fresh VM, so never commit one taken from a VM.
