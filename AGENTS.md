# Agent contract

Rules for AI/agent sessions in this repo.

## Ownership

- This repo is the only source of truth for the homelab. `main` is authored
  source: hosts are provisioned with `nixos-anywhere` and pull `main`
  themselves with comin. There is no rendered branch and no second desired
  state.
- One owner per concern: inventory lives only in `modules/topology.nix`; a
  `services/<name>.nix` owns its service, firewall, routes, backups and
  monitoring wiring.
- `hosts/<name>/` holds hardware, disko and host identity only.

## Secrets

- No secret values in the repo, the Nix store, logs or CI artifacts. Ever.
- Secrets are `op://` references to the `homelab` vault, rendered by OpNix
  with one read-only service account every host shares. Anything a
  compromised host must not get (e.g. the break-glass SSH key) stays out of
  `homelab`.
- If a change seems to need a literal secret, stop: find the reference-based
  path or ask.
- Planned: runtime secrets rendered by OpenBao `bao-agent` into
  `/var/lib/secrets/`, the same file contract.

## Conventions

- Comments say only what the code cannot: gotchas, safety reasons, and facts
  it depends on that live somewhere else (hardware, vendors, external setup,
  other files). Keep them short; never restate the code or narrate history,
  which belongs in the commit message.
- Public repo: IPs and hostnames are fine to commit; nothing else sensitive.
- Hosts deploy themselves (comin); CI never reaches the lab or writes to the
  cache. The break-glass push (`nix run .#deploy`) goes over the LAN
  to the scoped `deploy` user, through opkssh or the break-glass key
  (docs/remote-access.md). Root SSH stays off.

## Validation

CI is the check of record: every PR runs the secret scan, workflow lint,
`nix fmt -- --ci`, `nix flake check` and a build of each changed host on its
own architecture. Before pushing, run the two that are quick and that CI
cannot fix for you:

```console
nix fmt
nix flake check
```

## Completion

Work lands as a PR, and merging to `main` deploys every changed host with no
further gate. The PR
description names the hosts and services changed, any secret references
added (never values; the 1Password items must exist before merge), and
rollback implications.
