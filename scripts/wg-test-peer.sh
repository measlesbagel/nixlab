# Joins a throwaway WireGuard peer to this host's wg0 from the network
# namespace "peer", over a veth pair, so `ip netns exec peer <command>` acts
# as a remote device. Run as root on the WireGuard endpoint, in a VM: the
# peer stays on wg0 until wg0 restarts.
# Usage: wg-test-peer <unused address in the WireGuard subnet>
peer=${1:?usage: wg-test-peer <address>}
endpoint=$(ip -4 -o addr show dev wg0 | awk '{ sub("/.*", "", $4); print $4 }')
port=$(wg show wg0 listen-port)
key=$(wg genkey)

# 192.0.2.0/24 is reserved for documentation, so it clashes with nothing.
ip netns add peer
ip link add wg-peer-veth type veth peer name veth netns peer
ip addr add 192.0.2.1/24 dev wg-peer-veth
ip link set wg-peer-veth up
ip -n peer addr add 192.0.2.2/24 dev veth
ip -n peer link set veth up

ip -n peer link add wg-peer type wireguard
ip netns exec peer wg set wg-peer private-key <(echo "$key") \
  peer "$(wg show wg0 public-key)" endpoint "192.0.2.1:$port" allowed-ips "$endpoint/32"
ip -n peer addr add "$peer" peer "$endpoint" dev wg-peer
ip -n peer link set wg-peer up
wg set wg0 peer "$(echo "$key" | wg pubkey)" allowed-ips "$peer/32"
