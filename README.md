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

```console
nix run .#deploy                # apply + confirm every host over the tailnet
nix run .#deploy -- seladonia   # one host
nixos-rebuild switch --flake .#seladonia   # manual floor, on the host
```

A switch the deployer does not confirm within 10 minutes rolls itself back,
so a bare `colmena apply` (no `deploy-confirm`) rolls back too, and so does
a never-proven boot that never becomes manageable (`modules/watchdog.nix`).
Hosts reboot into a new kernel by themselves at night, once idle
(`modules/reboot.nix`).

PRs run `ci.yml` (checks and a build of each changed host). On merge to
`main`, `cd.yml` builds each changed host, pushes it to the lab cache on
albipes and deploys over the tailnet; hosts never build. One-time setup:
[docs/ci-setup.md](docs/ci-setup.md).

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
