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
- **A peer.** From the repo root, run
  `nixlab-vm exec -- "set -euo pipefail; set -- 10.100.0.254; $(cat scripts/wg-test-peer.sh)"`.
  This is the script the boot test uses (`services/dns.nix`). It joins a
  throwaway WireGuard peer at `10.100.0.254` from the network namespace
  `peer`, over a veth, so `ip netns exec peer` asks through `wg0` and the
  firewall like a remote device. It exits 0 with no output.
- **Lab names, as a peer.** Run `nixlab-vm exec -- 'for h in seladonia albipes chilense leetzi elegans; do echo "$h $(ip netns exec peer $DIG +short @10.100.0.1 $h.lab.measlesbagel.dev)"; done; echo "id $(ip netns exec peer $DIG +short @10.100.0.1 id.measlesbagel.dev)"'`.
  The output is `seladonia 192.168.4.39`, `albipes 192.168.4.41`, `chilense 192.168.4.21`, `leetzi 192.168.4.51`, `elegans 192.168.4.50` and `id 192.168.4.39`.
  The boot test retries this for up to a minute, so retry an empty answer for as long before calling it a failure.
- **Peers only.** Run `nixlab-vm exec -- 'ip addr add 192.168.4.39/32 dev lo; $DIG -b 192.168.4.39 @10.100.0.1 seladonia.lab.measlesbagel.dev | grep status:; ip addr del 192.168.4.39/32 dev lo'`.
  The output shows `status: REFUSED`: seladonia's LAN address is not a peer.
- **Not on the LAN.** Run `nixlab-vm exec -- 'ss -lunp | grep unbound'`. The only socket is
  `10.100.0.1:53`.

## Gotchas

- Never ask from the host itself with a `10.100.0.0/24` source, such as
  `-b 10.100.0.1` or an address added to `lo`. `wireguard-nat` masquerades
  that traffic on `lo` to the address of whichever interface registered
  first. So the answer flips between NOERROR and REFUSED from boot to boot.
  Ask from the `peer` namespace. Real peers are not affected.
- `wg-test-peer.sh` is not idempotent: a second run fails at
  `ip netns add peer`. The peer stays on `wg0` until `wg0` restarts.
- The peer proves the handshake and the firewall path over a veth. It does not
  prove a peer reaching seladonia from the internet through the router.
- The public key changes on every fresh VM, so never commit one taken from a VM.
