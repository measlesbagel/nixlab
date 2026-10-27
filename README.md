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
- `.github/workflows/`: CI/CD

## Fleet

| Host | Role |
| --- | --- |
| seladonia | mini PC — services plane (edge, postgres, media apps) |
| albipes | NAS — ZFS, NFS (music, models), RustFS S3, Nix cache |
| chilense | desktop — personal computer, dev env, RTX 4090 |
| leetzi, elegans | Asus GX10 (GB10, aarch64) inference nodes |

Hosts are named after dwarf tarantulas: [docs/taxonomy.md](docs/taxonomy.md).

## Deploy

Merge to `main`. Every host runs [comin](https://github.com/nlewo/comin)
(`modules/comin.nix`): it polls `main`, builds its own
`nixosConfigurations.<host>` (pulling from the lab cache on albipes, which
hosts fill as they build) and switches. GitHub holds no credential that
reaches the lab; branch protection on `main` is the deploy gate.

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

PRs run `ci.yml` (checks and a build of each changed host); it publishes
nothing. One-time setup: [docs/ci-setup.md](docs/ci-setup.md).

## Provisioning

`nix run .#provision -- <host>` installs over the tailnet:
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
