# nixlab verification map

This is the maintained recipe list for proving seladonia's behaviour in a
disposable VM (see `../SKILL.md`), plus the flake's host-side operator tools.
Read the baseline below, then use the matching feature file.

## Baseline preconditions

- `nixlab-vm launch seladonia` printed `export NIXLAB_VM_RUN=…`, and you
  exported it.
- `nixlab-vm doctor` prints `doctor: OK`.
- The VM is freshly booted, because these recipes assume first-boot state (an
  empty postgres and a newly made WireGuard key). Relaunch rather than reuse a
  VM that another recipe has changed.

## Driving conventions

- Write `nixlab-vm` for `.claude/skills/verify-nixlab/nixlab-vm`, run from the
  repo root.
- Run commands inside the VM with `nixlab-vm exec -- '<cmd>'`. Run commands on
  this machine with `nixlab-vm host -- <cmd>`.
- Wait on state, not sleeps: `systemctl is-active`, or `until …; do sleep 1;
  done` inside one `exec`.
- Run commands literally as written. The VM has no pager or TTY, so pass
  `--no-pager`.

## Proof and skip reporting

- A proof has three parts: the operator action, its result, and a second
  read-only view of any state the action changed. All three must be in
  `.verify/<run>/transcript.md`.
- Expected failures caused by missing secrets or network are not proofs that
  something works, and they are not regressions either. Report them as
  "not verifiable in VM" with the unit name.
- A new failure in a unit outside the expected-failure list is a regression
  until you can show otherwise.
- Do not report a skipped entry point as verified through a different path.

## Expected failures on seladonia

There is no OpNix token, no LAN and no internet. Observed on a fresh VM:

- Failed: `cloudflare-dyndns`, `pocket-id` and `upsmon` (no secrets, and the UPS
  server is on albipes).
- Stuck in `activating`/`auto-restart`: `acme-order-renew-measlesbagel.dev`.
  `caddy` stays active on NixOS's self-signed placeholder certificate, so a
  running caddy proves nothing about TLS.
- Inactive: `onepassword-secrets` and `media-music.mount`. `navidrome` is
  active, but `/media/music` is unreachable.
- Timers only, never fired: `restic-backups-nas.timer`.

`systemctl is-system-running` is `degraded` because of these. Check this list
against `systemctl --failed` whenever the services change.

## Features

- [Boot and health](./boot-health.md): the host boots its ZFS layout, and
  `deploy-health` passes.
- [Deploy confirmation](./deploy-confirm.md): `deploy-confirm` records the
  running system as the rollback target.
- [ZFS datasets and snapshots](./zfs-snapshots.md): the disko datasets, and
  sanoid snapshotting the `state` datasets.
- [PostgreSQL and its backup](./postgres.md): the server is up, and the
  dump job writes a backup.
- [WireGuard DNS](./wireguard-dns.md): unbound on `10.100.0.1` answers lab
  names.
- [Host-side tools](./host-tools.md): `changed-hosts` and
  `provision --dry-run`, run on this machine.
