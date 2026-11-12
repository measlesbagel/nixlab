# nixlab

Bare-metal NixOS homelab monorepo, the public source of truth for the fleet.

## Layout

- `hosts/<name>/`: one machine's hardware, disks and identity
- `modules/`: shared platform modules; `topology.nix` is the fleet inventory
- `services/`: one file per feature, owning its service, routes, backups and
  monitoring
- `home/measles/`: personal hjem config (hjem-rum modules)
- `installer/`, `scripts/`: the kexec installer, `provision` and a boot-test
  helper
- `secrets/`: secret contracts; never values
- `tests/`: evaluation checks run by `nix flake check`
- `.github/workflows/`: CI/CD

## Fleet

| Host | Role |
| --- | --- |
| seladonia | mini PC — services plane (edge, postgres, media apps) |
| albipes | NAS — btrfs RAID1, NFS (music, models), RustFS S3 |
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
the host's disko layout, sets the system profile and installs the bootloader
on them, boots that under KVM and runs the checks that the host's modules add
to `homelab.vmTest.checks` (`modules/vm-test.nix`).

What boots is the host's own configuration plus NixOS's test instrumentation,
on disks named `/dev/vdX`, with 1 GiB of RAM, fixed by disko. `/nix/store` is
shared from the build machine and `nixos-install` never runs, so the test
does not show that the closure copies onto the disk or fits there. The VM has
no LAN, internet, 1Password token, GPU, 10GbE uplink, UPS or SMART data.
comin runs in it as on the host, and only the Nix build sandbox keeps it from
pulling `main`, so keep the sandbox on.

The last check fails the test when the boot does not finish, or when a unit
has failed, is restarting, was restarted by its own `Restart=`, or was skipped
because a dependency failed. Units in `homelab.vmTest.unverifiable` are
excused because they need what the VM lacks, which includes every service
that reads a 1Password secret. The test log lists each as `not verified`, and
nothing about them is tested. The check also cannot see:

- a daemon whose parent exits 0 while its child dies, as `rpc.mountd` did
  (`modules/nfs-server.nix` checks that one itself);
- the restarts of a unit that a check started by hand, which resets the
  count;
- a unit skipped for a failed dependency before journald was up, in the
  initrd or just after it, as only the journal records a skip;
- what a timer would start: the test stops every timer so that the time of
  day cannot change its result, and a check starts what it tests.

CI runs it for each changed host marked `vmTest` in `flake.nix`, also when
only the test changed. The Sparks have none. To run one locally, on a machine
with KVM:

```console
nix build .#nixosConfigurations.seladonia.config.system.build.installTest -L
```

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

Every host but the Sparks is on btrfs, albipes's `tank` as RAID1 over
both drives. btrbk snapshots the subvolumes in `homelab.snapshots`, albipes
pulls those in `homelab.replicate` with btrbk, and restic ships the
postgres dump to RustFS. Everything is kept for two weeks. The Sparks hold
nothing to back up.

If a `tank` drive dies, albipes still boots, without `/tank`, and what
needs it stays down. Mount what is left, then swap the drive in
(`btrfs filesystem show` gives the missing devid):

```console
sudo mount -o degraded /dev/disk/by-partlabel/disk-data-b-btrfs /mnt/tank
sudo btrfs replace start <devid> /dev/disk/by-id/<new drive> /mnt/tank
```

Use `disk-data-a-btrfs` if data-b is the dead one, and reboot once the
replace is done to bring `/tank` back.

## Power

Every host is on one UPS, driven by albipes. At low battery they all shut
down, then power back on with mains (`modules/ups.nix`).

## Secrets

`op://` references rendered by OpNix; the rules are in
[AGENTS.md](AGENTS.md#secrets). An item must exist before the deploy that
first references it.
