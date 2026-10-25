# Moving albipes off UGOS

Provisioning albipes formats both 18 TB drives (`tank` in
`hosts/albipes/disko.nix`), and UGOS's btrfs-on-LVM volume cannot be
imported as ZFS. Only the music library comes back; the UGOS apps (lidarr,
slskd, beets, matrix) are rebuilt from scratch, their data left behind.

The copy taken in July 2026 lives on chilense at
`~/Backups/ugreen-evacuation-2026-07/payload/media/music/` (490 GB), and
chilense's own provisioning formats that disk, so: **albipes first,
restore and verify, and only then chilense.**

## 1. Final music pass from UGOS, right before cutover (optional)

Stop the writers, then sync whatever lidarr and slskd added since July.
`homelab-agent` is in the `docker` group and can read the whole library, so
neither step needs sudo. From chilense:

```console
ssh homelab-agent@192.168.4.41 'docker stop lidarr slskd beets navidrome'
rsync -aH --info=progress2 homelab-agent@192.168.4.41:/volume1/media/music/ ~/Backups/ugreen-evacuation-2026-07/payload/media/music/
```

Leave UGOS stopped from here on.

## 2. Provision albipes

provision logs in as root (the bootstrapTarget), so UGOS needs root SSH
enabled and your key in root's `authorized_keys`. From chilense:

```console
nix run .#provision -- albipes --bootstrap
```

From this point chilense holds the only copy. Do not touch it until step 4.

## 3. Restore

World-readable, because the NFS export squashes root:

```console
cd ~/Backups/ugreen-evacuation-2026-07
rsync -a --info=progress2 --rsync-path='sudo rsync' --chown=root:root --chmod=D755,F644 payload/media/music/ deploy@albipes:/tank/media/music/
```

## 4. Verify, then snapshot

A checksum comparison must list nothing:

```console
rsync -rnc --itemize-changes --rsync-path='sudo rsync' payload/media/music/ deploy@albipes:/tank/media/music/
ssh deploy@albipes 'sudo zfs snapshot tank/media@ugos-restore'
```

The manual snapshot is outside sanoid's retention, so it stays until deleted
by hand.

## 5. Only then: chilense

Provisioning chilense deletes the last copy outside the NAS. The mirror
survives a drive failure, not losing the box; until there is an off-site
copy, consider an external drive first.

Delete this file once the migration is done.
