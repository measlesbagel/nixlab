# Boot and health

seladonia boots from its disko layout (ZFS `rpool`, systemd-boot over EFI)
into multi-user. `deploy-health` is the check that comin and `deploy-confirm`
rely on, and it passes: sshd, unbound and WireGuard are all active.

## Sub-features

- `boot-zfs-root`: `/` comes from `rpool/local/root`, and the pool imports at boot.
- `boot-multi-user`: `multi-user.target` is reached, and the only failed units
  are on the expected-failure list.
- `boot-health`: `deploy-health` exits 0.

## How to get to it (user POV)

- Power on the host and log in on the console.
- On the host, run `deploy-health`, which `deploy-confirm` and comin also call.

## Driving it with nixlab-vm

Preconditions:

- The baseline is met, with a fresh VM.

Steps:

- **Network is sealed.** `nixlab-vm doctor` prints `network: LAN and internet unreachable`. To show it directly, run `nixlab-vm exec -- 'ip route; timeout 3 bash -c "</dev/tcp/127.0.0.1/5432" && echo local-ok'`.
  The output has no default route, only `10.0.2.0/24` and `10.100.0.0/24`, and prints `local-ok`, which proves the probe works at all.
- **Root is ZFS.** Run `nixlab-vm exec -- 'findmnt -no SOURCE,FSTYPE /; zpool list -H -o name,health'`.
  The output shows `rpool/local/root zfs` and `rpool ONLINE`.
- **Boot reached multi-user.** Run `nixlab-vm exec -- 'systemctl is-active multi-user.target; systemctl --failed --no-legend --plain'`.
  The output starts with `active`. Every failed unit is on the expected-failure
  list in `README.md`.
- **Health passes.** Run `nixlab-vm exec -- 'deploy-health && echo healthy'`. It exits 0
  and prints `healthy`.
- **Health catches a failure.** Run `nixlab-vm exec -- 'systemctl stop unbound; deploy-health; echo rc=$?; systemctl start unbound'`.
  The output shows `rc=3`, the exit code of `systemctl is-active` for an inactive unit. Then run
  `nixlab-vm exec -- 'deploy-health && echo healthy'`, which prints `healthy`
  again.

## Gotchas

- `systemctl is-system-running` reports `degraded` in every VM run because of
  the expected secret failures. Do not treat that as a failure on its own.
- `deploy-health` checks only sshd plus each service's `homelab.watchdog.healthChecks`.
  A service with no health check can be down while `deploy-health` passes.
- The VM disables the deploy-watchdog boot timer and the rollback path, so a
  boot that never becomes healthy is not rolled back here.
