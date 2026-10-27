---
name: verify-nixlab
description: Prove a nixlab host change works by booting that host's real NixOS configuration as a disposable QEMU VM on its disko/ZFS layout, then driving it as root over the serial console (systemctl, psql, dig, zfs) and running the flake's host-side apps (changed-hosts, provision --dry-run). Use after editing hosts/, modules/ or services/ when `nix flake check` is not proof enough, or when asked to verify, smoke-test or demo a nixlab change.
---

# Verify nixlab

nixlab is a NixOS fleet, so a user is an operator: they boot a host and run
commands on it. The real hosts are not a safe place to test (merging to `main`
deploys them, and some are not provisioned yet). Verification uses a stand-in
instead: the host's own `nixosConfigurations.<host>` booted as a QEMU VM, with
its disko layout on scratch qcow2 disks. Everything is done through
[`nixlab-vm`](nixlab-vm), which builds the VM from [`vm.nix`](vm.nix).

Only **seladonia** is proven to work this way. Its features are in
[features/README.md](features/README.md). Read that before you drive anything.

## Hard rules

- Never run `nix run .#deploy`, `colmena apply` or `provision` without
  `--dry-run`. They reach the real LAN machines. Never SSH to a `192.168.4.x`
  address.
- Drive only a VM this run launched (`NIXLAB_VM_RUN`). Never kill qemu or tmux
  by name.
- No secret values, not even fakes. Services that need an `op://` secret fail
  in the VM. Report them as not verified (see the feature map); don't stub
  them.
- `vm.nix` loads the repo as a git flake, so it can't see untracked files.
  `git add` a new module before you launch.

## Launch

```console
.claude/skills/verify-nixlab/nixlab-vm launch seladonia
export NIXLAB_VM_RUN=seladonia-20261027-093605-1109000   # the line launch printed
```

Launch builds the VM, which takes a long time the first time because it
compiles a ZFS kernel. Expect about 10 minutes, and run it in the background.
Launch then boots the VM in tmux session `nixlab-vm-$NIXLAB_VM_RUN` (on a private `tmux -L nixlab-vm`
server) and logs in
as root on the serial console. It is ready when it prints
`export NIXLAB_VM_RUN=…`, which happens after the root shell answers. The VM
has a 4 GiB, 4-core KVM guest and a restricted network: there is no LAN and no
internet, and the host's `/nix/store` is shared, so anything you `nix build` on this machine can be run from inside the VM. Two runs can run side
by side because they share no ports or disks.

## Doctor

```console
.claude/skills/verify-nixlab/nixlab-vm doctor
```

Doctor is read-only. It checks five things:

- the tmux session and qemu are up
- from inside the VM, seladonia's and albipes's LAN IPs and GitHub cannot be
  reached (`network: LAN and internet unreachable`)
- `systemd-detect-virt` is `kvm` or `qemu`, so this is not a real host
- the hostname matches
- `/run/current-system` is the toplevel this run built

It also prints `systemctl is-system-running`, which will show `degraded`
because of the expected secret failures. Run doctor first, and again whenever
output looks wrong. If it prints `doctor: FAIL`, tear down and relaunch.

## Drive

```console
nixlab-vm exec -- 'systemctl is-active postgresql'    # root shell in the VM
nixlab-vm host -- nix run .#changed-hosts -- HEAD~1   # this machine, at the repo root
```

`exec` sends the command over the serial console, base64-wrapped, so you can
use any quoting or a multi-line script. It prints the combined stdout and
stderr and returns the VM's exit code. A command waits up to
`NIXLAB_VM_TIMEOUT` seconds (default 120). After that the helper sends
Ctrl-C to free the console and exits non-zero. A command that reads stdin, such
as `grep pattern $EMPTY_VAR`, hangs until the timeout. The console is 250 columns wide,
and nothing runs interactively, so pass `--no-pager`, `-y` and similar flags.
`host` runs a command locally and records it in the same transcript.

## Evidence

Each run writes to `.verify/<run-id>/`, which is gitignored and survives
teardown:

- `transcript.md`: every `exec` and `host` call, with its command, output and
  exit code
- `console.log`: the raw serial console from firmware onwards
- `run.env`: the host, the git revision (`-dirty` if there are uncommitted
  edits) and the toplevel under test

A proof is a state change you caused through the operator path, plus a second,
read-only view of that state: for example, `deploy-confirm`, then `cat` the
file it wrote. One green `is-active` is not a proof. Cite the transcript
entries in your report, and list every feature you skipped along with its
reason.

## Cleanup

```console
.claude/skills/verify-nixlab/nixlab-vm teardown
```

Cleanup stops the qemu that this run started (the child of its tmux pane),
kills the session and deletes the scratch disks under
`$XDG_RUNTIME_DIR/nixlab-vm/<run-id>`. It keeps `.verify/<run-id>/`. Run it
after failed attempts as well. Delete old `.verify/` runs by hand when you no
longer need them.

## What the VM does not prove

These steps happen on the real target but never in the stand-in. Report them
as unverified whenever a change touches them.

- Disks: disko runs on scratch qcow2 files, not on the by-id NVMe. ZFS imports
  by UUID (`boot.zfs.devNodes`), not by id.
- Hardware: i40e jumbo frames (`homelab.lan.uplinkDrivers`), the
  `sp5100_tco` watchdog, AMD microcode and firmware.
- Deploy path: comin (disabled, because it would switch the VM to `main`), the
  deploy-watchdog boot timer and the rollback path (disabled, as in the host's
  `vmVariant`), and nightly reboots.
- Secrets: OpNix has no `/etc/opnix-token`, so ACME, Caddy's certificate,
  Pocket ID, DDNS and restic fail.
- Network: the LAN and the internet (Navidrome's NFS from albipes, the RustFS
  backup, the Attic substituter, WireGuard peers), and DNS answered from the
  real LAN.
- Provisioning: the kexec and nixos-anywhere install, which only
  `provision --dry-run` approaches.
- The other hosts. The Sparks (leetzi, elegans) are aarch64 and need GPU
  firmware, albipes needs its data drives, and chilense needs its 4090 and
  desktop. `nixlab-vm launch <host>` may build some of them, but it is
  unproven.
