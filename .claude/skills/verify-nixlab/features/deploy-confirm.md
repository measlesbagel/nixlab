# Deploy confirmation

`deploy-confirm` is the operator's (and comin's) way of telling the watchdog
that this system is good. It records the running system as the rollback
target and pins it as a GC root. It refuses to confirm when `deploy-health`
fails.

## Sub-features

- `confirm-record`: writes `/var/lib/deploy-watchdog/confirmed`, which points to `/run/current-system`.
- `confirm-gcroot`: `/nix/var/nix/gcroots/deploy-confirmed` points to the same path.
- `confirm-refuse`: fails, and records nothing, while `deploy-health` fails.

## How to get to it (user POV)

- `nix run .#deploy -- <host>` runs it after `colmena apply`. This entry point
  is never driven here.
- comin's post-deploy hook runs it once health is green and GitHub is reachable.
  comin is disabled in the VM.
- An operator on the host runs `sudo deploy-confirm`.

## Driving it with nixlab-vm

Preconditions:

- The baseline is met, and `deploy-health` passes (see `boot-health.md`).

Steps:

- **Nothing confirmed yet.** Run `nixlab-vm exec -- 'cat /var/lib/deploy-watchdog/confirmed 2>&1; true'`.
  On a fresh VM it reports `No such file`.
- **Refuse while unhealthy.** Run `nixlab-vm exec -- 'systemctl stop unbound; deploy-confirm; echo rc=$?; systemctl start unbound; ls /var/lib/deploy-watchdog/ 2>&1'`.
  `rc` is non-zero (3, from `systemctl is-active`), and `ls` reports that `/var/lib/deploy-watchdog/` does not exist.
- **Confirm.** Run `nixlab-vm exec -- 'deploy-confirm'`. It exits 0 and prints
  `confirmed /nix/store/…-nixos-system-seladonia-…`.
- **Second view.** Run `nixlab-vm exec -- 'cat /var/lib/deploy-watchdog/confirmed; readlink -f /run/current-system /nix/var/nix/gcroots/deploy-confirmed'`.
  All three paths are the same, and they match `toplevel` in `.verify/<run>/run.env`.

## Gotchas

- The refusal step must restart unbound, or every later recipe sees a broken
  health check.
- The confirm state persists until the VM restarts, so relaunch before you
  re-prove "nothing confirmed yet".
- Rollback itself (`deploy-revert`, `deploy-rollback.path`) cannot be proven
  here, because the VM disables it as the host's `vmVariant` does.
