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
# Inputs (environment, optional):
#   OPNIX_TOKEN or OPNIX_TOKEN_REF  the hosts' 1Password service-account token, or
#                                   an op:// reference to it (default below)
#
# The installer keeps the machine's LAN address (installer/default.nix), and
# deploy@ takes only opkssh or the break-glass key, so run this from chilense.

usage() {
  cat >&2 << 'USAGE'
usage: provision <host> [--bootstrap] [--dry-run] [-- <extra nixos-anywhere args>]
  --bootstrap  take over the pre-NixOS OS via the host's bootstrapTarget
  --dry-run    build the installer tarball and print commands only
env: OPNIX_TOKEN or OPNIX_TOKEN_REF (optional)
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

if [ "$bootstrap" = 1 ]; then
  target=$(jq -er '.bootstrapTarget // empty' <<< "$node") || {
    echo "$host has no bootstrapTarget in topology.nix" >&2
    exit 2
  }
else
  target="deploy@$ip"
fi

# Everything secret lives in memory only and is wiped on exit.
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/provision.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

if [ "$dryRun" = 1 ]; then
  opnixToken=dry-run
else
  opnixToken=${OPNIX_TOKEN:-$(op read "${OPNIX_TOKEN_REF:-op://private/nixlab-opnix/credential}")}
fi

system=$(jq -r .system <<< "$node")
kexec=$(nix build --no-link --print-out-paths "@flake@#packages.$system.kexec-installer")

mkdir -p "$work/extra/etc/ssh"
install -m 600 /dev/null "$work/extra/etc/opnix-token"
printf '%s' "$opnixToken" > "$work/extra/etc/opnix-token"

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
# a Spark kernel no cache has takes hours to build here under emulation.
# nixos-anywhere hands the installer the host's own substituters (graham33,
# Flox, lab cache), so it only builds what none of them have.
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
