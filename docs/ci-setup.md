# CI/CD one-time setup

Configured outside the repo, once. GitHub only verifies: hosts pull `main`
and deploy themselves (`modules/comin.nix`), so no secret goes in GitHub and
nothing in it reaches the lab. The policy workflow reaches Tailscale's API
through OIDC workload identity.

## GitHub

1. Create `measlesbagel/nixlab`, public, with pull requests restricted to
   collaborators (Settings > General > Features; UI only).
2. Actions: only GitHub-owned actions plus `DeterminateSystems/*`,
   `tailscale/*`, `gitleaks/*` and `zizmorcore/*`, SHA pinning required;
   approval for every outside contributor's run; a read-only default token
   that cannot approve PRs.
3. Ruleset `main`: require a pull request with code-owner review and the
   `Secret scan`, `Workflow lint` and `Flake check` status checks; block
   force pushes and deletion; repository admins bypass. (`Build <host>`
   exists only for changed hosts, so it cannot be required by name.)
   `.github/CODEOWNERS` makes the owner review every PR, so agent accounts
   cannot merge their own. This ruleset is the deploy gate: every host
   applies whatever lands on `main`, provided GitHub signed the tip commit
   (`modules/comin.nix`). Merge in the web UI; a commit pushed straight to
   `main`, even by an admin, is not deployed until a signed one lands on top.
4. Environment `production`: deployment branches limited to `main`; no
   reviewers.
5. Secret scanning with push protection, Dependabot alerts and private
   vulnerability reporting.
6. First push: `[skip ci]` in the head commit, then
   `gh workflow disable tailscale-policy` until the hosts are provisioned.
7. Repository variables (public identifiers, not secrets): `TS_TAILNET`,
   `TS_POLICY_READ_CLIENT_ID`, `TS_POLICY_READ_AUDIENCE`,
   `TS_POLICY_WRITE_CLIENT_ID`, `TS_POLICY_WRITE_AUDIENCE`.

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

   Use each credential's client ID and audience for the matching variables.

### Tailnet Lock (after provisioning)

Once albipes and chilense are up, make them the signing nodes and enable
Tailnet Lock; the disablement secrets go in the `private` vault. In the same
change, `provision.sh` pre-signs the keys it mints with `tailscale lock sign`,
so it must run on a signing node. No CI job joins the tailnet.

## Lab binary cache

Each host builds its own system, pulling from Attic on albipes
(`services/attic.nix`) over the LAN, then cache.nixos.org, and pushes what it
built back to Attic (`modules/cache.nix`). leetzi hands its builds to elegans
(`modules/remote-builder.nix`), so the Spark kernel compiles once. CI never
writes to the cache: a push token can poison what every host substitutes.

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

Then make the hosts' push token and store it at `op://homelab/attic-push/token`
before the change that sets the public key merges:

```console
sudo atticd-atticadm make-token --sub hosts --validity 1y --push nixlab --pull nixlab
```

Commit the printed public key as `homelab.cache.publicKey`, at its default in
`modules/cache.nix`; it is public by design. Until it is set, hosts neither
pull from nor push to the cache.

The cache is public for reads, which is safe because nothing secret is ever in
the Nix store. It is reachable only on the LAN.

## Remote builder (leetzi → elegans)

Once both Sparks are provisioned, commit each one's
`/etc/ssh/ssh_host_ed25519_key.pub` as `sshHostKey` in `modules/topology.nix`.
leetzi then builds on elegans as `nix-builder` over the ConnectX-7 link,
authenticated by its host key; until both are set, each Spark builds alone.
