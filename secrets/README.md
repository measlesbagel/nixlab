# secrets/

Contracts only, never values.

Secrets are `op://` references declared by the feature that uses them; OpNix
renders them to `/var/lib/opnix/secrets/<key>` at activation.

Planned, not built: a spec here for auto-minted secrets (host keys, random
service credentials), consumed by `nix run .#gen-secrets`, which would create
missing 1Password items under deterministic names
(`op://homelab-generated/<host>-<name>/<field>`) so references can exist
before the items do.
