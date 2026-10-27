# Provision (or reinstall) a host with nixos-anywhere over the LAN.
# Wrapped by `nix run .#provision`; @-placeholders are filled in by flake.nix.
#
#   provision <host> [--bootstrap] [--dry-run] [-- <extra nixos-anywhere args>]
#
#   --bootstrap  take over the machine's pre-NixOS OS via its bootstrapTarget
#                (topology.nix); otherwise take over deploy@<host's LAN IP>.
#   --dry-run    build the installer tarball and print the commands, but do not
#                connect to anything.
#
# Inputs (environment, all optional):
#   OPNIX_TOKEN or OPNIX_TOKEN_REF  the hosts' 1Password service-account token, or
#                                   an op:// reference to it (default below)
#   TS_HOST_AUTHKEY                 the installed host's tailnet join key; by
#                                   default minted single-use with the
#                                   provisioning OAuth client
#
# The installer keeps the machine's LAN address (installer/default.nix), and
# deploy@ takes only opkssh or the break-glass key, so run this from chilense.
# The OAuth client (Auth Keys write scope, tag:molt, which owns every host tag
# in tailscale/policy.hujson) lives only in the admin's vault. Hosts never see
# it: each gets a key that joins one device, with its own tags, once.

usage() {
  cat >&2 << 'USAGE'
usage: provision <host> [--bootstrap] [--dry-run] [-- <extra nixos-anywhere args>]
  --bootstrap  take over the pre-NixOS OS via the host's bootstrapTarget
  --dry-run    build the installer tarball and print commands only
env: OPNIX_TOKEN or OPNIX_TOKEN_REF, TS_HOST_AUTHKEY (all optional)
USAGE
  exit 2
}

host=""
bootstrap=0
dryRun=0
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --bootstrap) bootstrap=1 ;;
    --dry-run) dryRun=1 ;;
    -h | --help) usage ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    -*) usage ;;
    *) host="$1" ;;
  esac
  shift
done
[ -n "$host" ] || usage

nodes='@nodes@'
node=$(jq -ce --arg h "$host" '.[$h] // empty' <<< "$nodes") || {
  echo "unknown host: $host" >&2
  exit 2
}
ip=$(jq -r .ip <<< "$node")
tsName=$(jq -r .tailscaleName <<< "$node")

if [ "$bootstrap" = 1 ]; then
  target=$(jq -er '.bootstrapTarget // empty' <<< "$node") || {
    echo "$host has no bootstrapTarget in topology.nix" >&2
    exit 2
  }
else
  target="deploy@$ip"
  echo "note: if $tsName stays registered in the tailnet, the reinstalled host" >&2
  echo "      joins as $tsName-1; remove the old machine in the admin console." >&2
fi

# Everything secret lives in memory only and is wiped on exit.
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/provision.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

# Mint a single-use, preauthorized key that expires in a day if unused.
#   mint <tags as a JSON array>
mint() {
  jq -nc --argjson tags "$1" '{
    capabilities: {devices: {create: {
      reusable: false, ephemeral: false, preauthorized: true, tags: $tags}}},
    expirySeconds: 86400, description: "nixlab provision"}' |
    curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$tsAccess") \
      -H 'Content-Type: application/json' --data @- \
      https://api.tailscale.com/api/v2/tailnet/-/keys |
    jq -er .key
}

if [ "$dryRun" = 1 ]; then
  # Nothing is minted or read: the key would be consumed for nothing.
  hostAuthkey=dry-run opnixToken=dry-run
else
  if [ -z "${TS_HOST_AUTHKEY:-}" ]; then
    # An API access token, valid for an hour, from the provisioning client.
    tsAccess=$(curl -fsS https://api.tailscale.com/api/v2/oauth/token \
      --data-urlencode "client_id=$(op read -n op://private/tailscale-provision/client-id)" \
      --data-urlencode "client_secret@"<(op read -n op://private/tailscale-provision/client-secret) |
      jq -er .access_token)
  fi
  hostAuthkey=${TS_HOST_AUTHKEY:-$(mint "$(jq -c .tailscaleTags <<< "$node")")}
  opnixToken=${OPNIX_TOKEN:-$(op read "${OPNIX_TOKEN_REF:-op://private/nixlab-opnix/credential}")}
fi

system=$(jq -r .system <<< "$node")
kexec=$(nix build --no-link --print-out-paths "@flake@#packages.$system.kexec-installer")

mkdir -p "$work/extra/etc/ssh" "$work/extra/var/lib/nixlab"
install -m 600 /dev/null "$work/extra/etc/opnix-token"
printf '%s' "$opnixToken" > "$work/extra/etc/opnix-token"
# Used once by tailscaled-autoconnect on first boot, then deleted
# (modules/tailscale.nix).
install -m 600 /dev/null "$work/extra/var/lib/nixlab/tailscale-authkey"
printf '%s' "$hostAuthkey" > "$work/extra/var/lib/nixlab/tailscale-authkey"

# The host key is made here so the installed host can be pinned from its first
# boot; sshd keeps an existing key.
ssh-keygen -q -t ed25519 -N "" -C "root@$host" -f "$work/extra/etc/ssh/ssh_host_ed25519_key"
hostKey=$(cut -d' ' -f1-2 "$work/extra/etc/ssh/ssh_host_ed25519_key.pub")
knownHosts="$work/known_hosts"
printf '%s %s\n' "$ip" "$hostKey" > "$knownHosts"

# In a dry run, print remote-touching commands instead of running them.
run() {
  if [ "$dryRun" = 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# A foreign-architecture host builds its own system on the installer, natively:
# nothing public caches the Spark kernel, and building it here under
# emulation takes hours. nixos-anywhere hands the installer the host's own
# substituters (lab cache, Flox), so it only builds what none of them have.
# Later deploys download it from the lab cache.
buildOn=()
if [ "$system" != "$(nix config show system)" ]; then
  buildOn=(--build-on remote)
fi

echo ">> installing $host via $target"
run nixos-anywhere --flake "@flake@#$host" --kexec "$kexec"/*.tar.gz "${buildOn[@]}" \
  --extra-files "$work/extra" --target-host "$target" "${extra[@]}"

echo ">> waiting for deploy@$ip to come back"
for _ in $(seq 90); do
  if [ "$dryRun" = 1 ] || ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o UserKnownHostsFile="$knownHosts" "deploy@$ip" true 2> /dev/null; then
    echo ">> $host is up. Pin its host key in modules/topology.nix:"
    echo "     sshHostKey = \"$hostKey\";"
    exit 0
  fi
  sleep 10
done
echo "$host did not come back within 15 minutes" >&2
exit 1
