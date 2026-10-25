# Provision (or reinstall) a host with nixos-anywhere over the tailnet.
# Wrapped by `nix run .#provision`; @-placeholders are filled in by flake.nix.
#
#   provision <host> [--bootstrap] [--dry-run] [-- <extra nixos-anywhere args>]
#
#   --bootstrap  take over the machine's pre-NixOS OS via its bootstrapTarget
#                (topology.nix); otherwise take over deploy@<host> over the tailnet.
#   --dry-run    build the installer tarball and print the commands, but do not
#                connect to anything.
#
# Inputs (environment, all optional):
#   OPNIX_TOKEN or OPNIX_TOKEN_REF  the hosts' 1Password service-account token, or
#                                   an op:// reference to it (default below)
#   TS_INSTALLER_AUTHKEY            join keys for the installer and the installed
#   TS_HOST_AUTHKEY                 host; by default both are minted single-use
#                                   with the provisioning OAuth client
#
# The OAuth client (Auth Keys write scope, tag:molt, which owns every
# host tag and tag:instar in tailscale/policy.hujson) lives only in the admin's vault. Hosts never see it: each
# gets a key that joins one device, with its own tags, once.

usage() {
  cat >&2 << 'USAGE'
usage: provision <host> [--bootstrap] [--dry-run] [-- <extra nixos-anywhere args>]
  --bootstrap  take over the pre-NixOS OS via the host's bootstrapTarget
  --dry-run    build the installer tarball and print commands only
env: OPNIX_TOKEN or OPNIX_TOKEN_REF, TS_INSTALLER_AUTHKEY, TS_HOST_AUTHKEY (all optional)
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
tsName=$(jq -r .tailscaleName <<< "$node")
installer="$tsName-installer"

if [ "$bootstrap" = 1 ]; then
  target=$(jq -er '.bootstrapTarget // empty' <<< "$node") || {
    echo "$host has no bootstrapTarget in topology.nix" >&2
    exit 2
  }
else
  target="deploy@$tsName"
  echo "note: if $tsName stays registered in the tailnet, the reinstalled host" >&2
  echo "      joins as $tsName-1; remove the old machine in the admin console." >&2
fi

# Everything secret lives in memory only and is wiped on exit.
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/dev/shm}/provision.XXXXXX")
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

# Mint a single-use, preauthorized key that expires in a day if unused.
#   mint <ephemeral: true|false> <tags as a JSON array>
mint() {
  jq -nc --argjson eph "$1" --argjson tags "$2" '{
    capabilities: {devices: {create: {
      reusable: false, ephemeral: $eph, preauthorized: true, tags: $tags}}},
    expirySeconds: 86400, description: "nixlab provision"}' |
    curl -fsS -H @<(printf 'Authorization: Bearer %s\n' "$tsAccess") \
      -H 'Content-Type: application/json' --data @- \
      https://api.tailscale.com/api/v2/tailnet/-/keys |
    jq -er .key
}

if [ "$dryRun" = 1 ]; then
  # Nothing is minted or read: the keys would be consumed for nothing.
  authkey=dry-run hostAuthkey=dry-run opnixToken=dry-run
else
  if [ -z "${TS_INSTALLER_AUTHKEY:-}" ] || [ -z "${TS_HOST_AUTHKEY:-}" ]; then
    # An API access token, valid for an hour, from the provisioning client.
    tsAccess=$(curl -fsS https://api.tailscale.com/api/v2/oauth/token \
      --data-urlencode "client_id=$(op read -n op://private/tailscale-provision/client-id)" \
      --data-urlencode "client_secret@"<(op read -n op://private/tailscale-provision/client-secret) |
      jq -er .access_token)
  fi
  authkey=${TS_INSTALLER_AUTHKEY:-$(mint true '["tag:instar"]')}
  hostAuthkey=${TS_HOST_AUTHKEY:-$(mint false "$(jq -c .tailscaleTags <<< "$node")")}
  opnixToken=${OPNIX_TOKEN:-$(op read "${OPNIX_TOKEN_REF:-op://private/nixlab-opnix/credential}")}
fi

# Installer tarball for the target's architecture, with the join key
# appended to its initrd. A foreign-architecture installer has to come from
# the lab cache or a builder for that system (e.g. qemu binfmt emulation).
system=$(jq -r .system <<< "$node")
kexec=$(nix build --no-link --print-out-paths "@flake@#packages.$system.kexec-installer")
tar -xzf "$kexec"/*.tar.gz -C "$work"
chmod -R u+w "$work/kexec"
mkdir -p "$work/inject/nixlab-installer"
printf '%s' "$authkey" > "$work/inject/nixlab-installer/authkey"
printf '%s' "$installer" > "$work/inject/nixlab-installer/hostname"
(cd "$work/inject" && find . | cpio -o -H newc --quiet | gzip -9) >> "$work/kexec/initrd"
rm -rf "$work/inject"
tar -czf "$work/installer.tar.gz" -C "$work" kexec
rm -rf "$work/kexec"

mkdir -p "$work/extra/etc" "$work/extra/var/lib/nixlab"
install -m 600 /dev/null "$work/extra/etc/opnix-token"
printf '%s' "$opnixToken" > "$work/extra/etc/opnix-token"
# Used once by tailscaled-autoconnect on first boot, then deleted
# (modules/tailscale.nix).
install -m 600 /dev/null "$work/extra/var/lib/nixlab/tailscale-authkey"
printf '%s' "$hostAuthkey" > "$work/extra/var/lib/nixlab/tailscale-authkey"

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
reachable() {
  [ "$dryRun" = 1 ] && return 0
  ssh -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    -o UserKnownHostsFile="$knownHosts" "$1" true 2> /dev/null
}

if [ "$dryRun" = 1 ]; then
  echo "dry run: built $(du -h "$work/installer.tar.gz" | cut -f1) installer for $installer"
fi

flake="@flake@#$host"
knownHosts="$work/known_hosts"

echo ">> phase 1: kexec $target into the installer"
run nixos-anywhere --flake "$flake" --phases kexec --kexec "$work/installer.tar.gz" \
  --target-host "$target" "${extra[@]}"

echo ">> waiting for $installer on the tailnet"
for _ in $(seq 60); do
  reachable "root@$installer" && break
  sleep 10
done
reachable "root@$installer" || {
  echo "$installer did not appear on the tailnet within 10 minutes" >&2
  exit 1
}

# A foreign-architecture host builds its own system on the installer, natively:
# nothing public caches the Spark kernel, and building it here under
# emulation takes hours. nixos-anywhere hands the installer the host's own
# substituters (lab cache, Flox), so it only builds what none of them have.
# Later deploys download it from the lab cache, built by CI.
buildOn=()
if [ "$system" != "$(nix config show system)" ]; then
  buildOn=(--build-on remote)
fi

echo ">> phase 2: install $host from $installer"
run nixos-anywhere --flake "$flake" --phases disko,install,reboot "${buildOn[@]}" \
  --extra-files "$work/extra" --target-host "root@$installer" \
  --ssh-option UserKnownHostsFile="$knownHosts" "${extra[@]}"

echo ">> waiting for $tsName to come back"
for _ in $(seq 90); do
  if reachable "deploy@$tsName"; then
    echo ">> $host is up"
    exit 0
  fi
  sleep 10
done
echo "$host did not rejoin the tailnet within 15 minutes" >&2
exit 1
