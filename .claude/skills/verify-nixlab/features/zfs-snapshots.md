# ZFS datasets and snapshots

seladonia's state lives on the disko datasets under `rpool/safe`. sanoid
snapshots the datasets listed in `homelab.zfs.snapshots` under the two-week
`state` policy.

## Sub-features

- `zfs-layout`: every disko dataset exists with its mountpoint, and postgres
  uses `recordsize=8K`.
- `zfs-sanoid-take`: a sanoid run takes `autosnap_*` snapshots of each `state` dataset.
- `zfs-sanoid-scope`: datasets that are not listed (`rpool/local/*`) get no snapshots.

## How to get to it (user POV)

- `zfs list` on the host.
- `sanoid.timer` fires every 15 minutes. An operator can run
  `systemctl start sanoid` to trigger it straight away.

## Driving it with nixlab-vm

Preconditions:

- The baseline is met.

Steps:

- **Layout.** Run `nixlab-vm exec -- 'zfs list -H -o name,mountpoint,recordsize -r rpool'`.
  The output lists `rpool/local/root /`, `rpool/local/nix /nix`,
  `rpool/safe/var-lib /var/lib`, `rpool/safe/navidrome /var/lib/navidrome`
  and `rpool/safe/postgres /var/lib/postgresql 8K`.
- **Take snapshots.** Run `nixlab-vm exec -- 'systemctl start sanoid.service; systemctl show -p Result --value sanoid.service'`.
  The output is `success`.
- **Second view.** Run `nixlab-vm exec -- 'zfs list -H -t snapshot -o name'`.
  It lists `<dataset>@autosnap_<date>_<time>_hourly` and `_daily` snapshots for
  `rpool/safe/var-lib`, `rpool/safe/navidrome` and `rpool/safe/postgres`, and
  none for `rpool/local/*`.

## Gotchas

- In the VM, `/nix` is `rpool/local/nix`, but `/nix/store` is an overlay of
  the host's store (virtiofs) on top of it. Store contents therefore prove
  nothing about the dataset.
- Replication (`homelab.zfs.replicate`, which albipes pulls with syncoid) needs
  albipes, so it cannot be verified here.
- sanoid only takes the snapshots that are due. A second immediate run adds
  nothing, and that is not a failure.
