# CI/CD one-time setup

Configured outside the repo, once. Tailscale access uses OIDC workload
identity and the cache push token is minted per run on albipes, so the only
secret in GitHub is the Dependabot cache-read key below, which reaches nothing
but public cache reads.

## GitHub

1. Create `measlesbagel/nixlab`, public, with pull requests restricted to
   collaborators (Settings > General > Features; UI only).
2. Actions: only GitHub-owned actions plus `DeterminateSystems/*`,
   `tailscale/*`, `gitleaks/*` and `zizmorcore/*`, SHA pinning required;
   approval for every outside contributor's run; a read-only default token
   that cannot approve PRs.
3. Ruleset `main`: require a pull request with code-owner review and the
   `Secret scan`, `Workflow lint` and `Flake check` status checks; block
   force pushes and deletion; repository admins bypass. (`Build <host>` and
   `Release <host>` exist only for changed hosts, so they cannot be required
   by name.) `.github/CODEOWNERS` makes the owner review every PR, so agent
   accounts cannot merge their own.
4. Environment `production`: deployment branches limited to `main`; no
   reviewers.
5. Secret scanning with push protection, Dependabot alerts and private
   vulnerability reporting.
6. First push: `[skip ci]` in the head commit, then
   `gh workflow disable cd` and `gh workflow disable tailscale-policy` until
   the hosts are provisioned.
7. Repository variables (public identifiers, not secrets): `TS_TAILNET`,
   `TS_POLICY_READ_CLIENT_ID`, `TS_POLICY_READ_AUDIENCE`,
   `TS_POLICY_WRITE_CLIENT_ID`, `TS_POLICY_WRITE_AUDIENCE`,
   `TS_DEPLOY_CLIENT_ID`, `TS_DEPLOY_AUDIENCE`, `TS_CACHE_CLIENT_ID`,
   `TS_CACHE_AUDIENCE`.
8. Dependabot secret `TS_CACHE_AUTHKEY` (Settings > Secrets and variables >
   Dependabot): see the cache-read key under Tailscale. Dependabot runs get
   no OIDC token, so this is how their builds reach the lab cache.

## Tailscale

1. Create the tailnet and enable MagicDNS.
2. Paste `tailscale/policy.hujson` into the access-controls editor by hand the
   first time; it validates the file and runs its tests. From then on the
   `tailscale-policy` workflow owns it.
3. Provisioning credential: an OAuth client with only the Auth Keys write
   scope and the single tag `tag:molt`, which the policy makes owner of
   every host tag and `tag:instar` (an OAuth client can only mint keys for
   several tags through such an owner tag). Its client ID and secret go in
   the admin's own vault at
   `op://private/tailscale-provision/{client-id,client-secret}`, never in
   `homelab`: hosts must never see it.
4. Federated identities (Settings, Trust credentials), issuer
   `https://token.actions.githubusercontent.com`:

   | Use | Subject | Scope |
   | --- | --- | --- |
   | policy test | `repo:measlesbagel/nixlab:pull_request` | policy file, read-only |
   | policy apply | `repo:measlesbagel/nixlab:environment:production` | policy file |
   | deploy | `repo:measlesbagel/nixlab:environment:production` | `auth_keys`, tag `tag:hatch` |
   | cache read | `repo:measlesbagel/nixlab:pull_request` | `auth_keys`, tag `tag:larva` |

   Use each credential's client ID and audience for the matching variables.
5. Cache-read key for Dependabot: an auth key that is reusable, ephemeral and
   pre-approved, tagged `tag:larva`, with the longest expiry (90 days). Store
   it as the `TS_CACHE_AUTHKEY` Dependabot secret and rotate it before it
   expires; an expired key only makes Dependabot builds skip the cache.
   `tag:larva` reaches only Attic on albipes, so a leaked key exposes nothing
   that is not already public.

### Tailnet Lock (after provisioning)

Once albipes and chilense are up, make them the signing nodes and enable
Tailnet Lock; the disablement secrets go in the `private` vault. In the same
change:

- `provision.sh` pre-signs the keys it mints with `tailscale lock sign`, so
  it must run on a signing node.
- The `tag:larva` cache-read key must be re-minted pre-signed, and PR builds
  from branches lose the cache (their OIDC identity cannot be pre-signed)
  unless they switch to that key too.
- `cd.yml` cannot use the OAuth/OIDC identity on a locked tailnet: the action
  needs a reusable, ephemeral, pre-signed auth key with `tag:hatch`, stored
  as a `production` environment secret and rotated before its 90-day expiry.
  `tag:hatch` can deploy every host, so treat that key accordingly.

## Lab binary cache

CI builds each changed host on a runner of its architecture
(`ubuntu-24.04-arm` for aarch64), pushes the closure to Attic on albipes
(`services/attic.nix`) and deploys. Hosts take what they can from the cache
over the LAN and the rest from the runner.

PR builds pull from the same cache over the tailnet as `tag:larva`, with no
Attic token, so the NVIDIA kernel compiles once per kernel change rather than
on every PR. They use it only once `homelab.cache.publicKey` is set, and fall
back to building when it is unreachable. Fork PRs get no credential and build
from public caches alone.

The token-signing key lives at `op://homelab/attic-server-env/env`. atticd
generates the NAR signing key when the cache is created, so once albipes
has first booted:

```console
ssh deploy@albipes
token=$(sudo atticd-atticadm make-token --sub admin --validity 10m \
  --create-cache nixlab --configure-cache nixlab --pull nixlab --push nixlab)
nix run nixpkgs#attic-client -- login local http://localhost:7313 "$token"
nix run nixpkgs#attic-client -- cache create local:nixlab --public
nix run nixpkgs#attic-client -- cache info local:nixlab   # prints the public key
```

Commit the printed public key as `homelab.cache.publicKey`, at its default in
`modules/cache.nix`; it is public by design. Until it is set, hosts skip the
cache.

A manual `nix run .#deploy -- <host>` builds on the machine running it, so
deploying an aarch64 host from chilense only works for closures CI has
already pushed.

The cache is public for reads, which is safe because nothing secret is ever in
the Nix store. It is reachable only on the LAN and, for CI, the tailnet.
