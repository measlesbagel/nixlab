# nixlab

Bare-metal NixOS homelab monorepo, the public source of truth for the fleet.

## Layout

- `hosts/<name>/`: one machine's hardware, disks and identity
- `modules/`: shared platform modules; `topology.nix` is the fleet inventory
- `services/`: one file per feature, owning its service, routes, backups and
  monitoring
- `home/measles/`: personal hjem config (hjem-rum modules)
- `installer/`, `scripts/`: the kexec installer and `provision`
- `secrets/`: secret contracts; never values
- `tests/`: evaluation checks run by `nix flake check`
- `.github/workflows/`: CI/CD

## Fleet

| Host | Role |
| --- | --- |
| seladonia | mini PC — services plane (edge, postgres, media apps) |
| albipes | NAS — ZFS, NFS (music, models), RustFS S3 |
| chilense | desktop — personal computer, dev env, RTX 4090 |
| leetzi, elegans | Asus GX10 (GB10, aarch64) inference nodes |

Hosts are named after dwarf tarantulas: [docs/taxonomy.md](docs/taxonomy.md).

## Deploy

Merge to `main`. Every host runs [comin](https://github.com/nlewo/comin)
(`modules/comin.nix`): it polls `main`, builds its own
`nixosConfigurations.<host>` (pulling from the public Cachix cache that CI
fills) and switches. GitHub holds no credential that reaches the lab, and
branch protection on `main` gates what hosts build. The Cachix token can still
change what they substitute ([docs/ci-setup.md](docs/ci-setup.md)).

```console
comin status                    # on a host: what it runs and what it's doing
nix run .#deploy -- seladonia   # break-glass push from chilense, then confirm
nixos-rebuild switch --flake .#seladonia   # manual floor, on the host
```

A switch nobody confirms within 10 minutes rolls itself back, and so does a
never-proven boot that never becomes manageable (`modules/watchdog.nix`).
comin confirms only once the host passes `deploy-health` and can still reach
GitHub. Hosts reboot into a new kernel by themselves at night, once idle
(`modules/reboot.nix`).

PRs run `ci.yml` (checks, a build of each changed host and a boot test of
each changed x86_64 host) and keep one comment with each changed host's
closure diff against the base
([nix-diff-action](https://github.com/natsukium/nix-diff-action), comparing
`.drv` files, so nothing builds twice). The sizes in it are `.drv` closures,
not runtime closures, and the action also uploads the full diff as a workflow
artifact. A same-repo PR also pushes what it built to the Cachix cache.
One-time setup: [docs/ci-setup.md](docs/ci-setup.md).

## Boot tests

A host's boot test is disko's `installTest`. It formats scratch disks from
the host's disko layout, installs the host's own system and bootloader,
boots it under KVM, and runs the checks that its modules add to
`disko.tests.extraChecks`. Once the boot settles, a unit that is failed or
restarting, or that its own `Restart=` restarts during the next 15 s, fails the
test. A unit may fail early and recover on a restart. Units in
`homelab.vmTest.unverifiable` are excused, because they need what a VM lacks:
1Password secrets, the LAN, or USB and SMART hardware
(`modules/vm-test.nix`). The check cannot see:
- an excused unit;
- a unit that systemd skipped because a dependency failed;
- a daemon whose parent exits 0 while its child dies, as `rpc.mountd` did
  (`modules/nfs-server.nix` checks that one itself);
- a restart that `Restart=` did not schedule (`Upholds=`, an `OnFailure=`
  handler, a manual restart), because it resets the restart count;
- a unit that stays up for over 15 s between crashes, or that first fails
  after the window.

CI runs it for each changed host marked `vmTest` in `flake.nix`. To run one
locally, on a machine with KVM:

```console
nix build .#nixosConfigurations.seladonia.config.system.build.installTest -L
```

The VM has 1 GiB of RAM and one vCPU, fixed by disko. It has no GPU, 10GbE
uplink, hardware watchdog, secrets, LAN or internet, so none of those are
tested. The Sparks have no boot test.

## Remote access

WireGuard to seladonia for getting in, and SSH logins through opkssh and
Pocket ID, with a LAN-only break-glass key:
[docs/remote-access.md](docs/remote-access.md).

## Provisioning

`nix run .#provision -- <host>` installs over the LAN:
[docs/provisioning.md](docs/provisioning.md).

## Models

One library on albipes, local copies on the hosts that run them:
[docs/models.md](docs/models.md).

## Storage

sanoid snapshots the datasets in `homelab.zfs.snapshots`, albipes pulls
those in `homelab.zfs.replicate` with `syncoid`, and restic ships the
postgres dump to RustFS. Everything is kept for two weeks. The Sparks hold
nothing to back up.

## Power

Every host is on one UPS, driven by albipes. At low battery they all shut
down, then power back on with mains (`modules/ups.nix`).

## Secrets

`op://` references rendered by OpNix; the rules are in
[AGENTS.md](AGENTS.md#secrets). An item must exist before the deploy that
first references it.
