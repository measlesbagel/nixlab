# CI/CD one-time setup

Configured outside the repo, once. GitHub only verifies: hosts pull `main`
and deploy themselves (`modules/comin.nix`), so no secret goes in GitHub and
nothing in it reaches the lab.

## GitHub

1. Create `measlesbagel/nixlab`, public, with pull requests restricted to
   collaborators (Settings > General > Features; UI only).
2. Actions: only GitHub-owned actions plus `DeterminateSystems/*`,
   `gitleaks/*` and `zizmorcore/*`, SHA pinning required;
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
4. Secret scanning with push protection, Dependabot alerts and private
   vulnerability reporting.
5. First push: `[skip ci]` in the head commit.

Remote access and SSH logins (WireGuard, Pocket ID, opkssh) are set up
once per [remote-access.md](remote-access.md).

## Public caches

Besides cache.nixos.org, the Sparks substitute from graham33.cachix.org
(`modules/spark.nix`), where upstream's full builds push the NVIDIA kernel,
and from cache.flox.dev for CUDA, which upstream's module adds. CI's build job
substitutes from each host's `nix.settings.extra-substituters`, so it
downloads what that host would.

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
the Nix store. Hosts use it on the LAN. CI reads it through
`https://cache.measlesbagel.dev/nixlab` (`services/attic-public.nix`): Caddy
on seladonia passes only `GET` and `HEAD` under `/nixlab/` and drops any
`Authorization` header, so the token API stays LAN-only. A PR that changes
nothing under the Spark kernel then downloads it instead of rebuilding it for
two hours; a kernel change graham33.cachix.org lacks still builds in full,
because CI runs before any host has built it. Each CI download counts against the home uplink.

## Remote builder (leetzi → elegans)

Once both Sparks are provisioned, commit each one's
`/etc/ssh/ssh_host_ed25519_key.pub` as `sshHostKey` in `modules/topology.nix`.
leetzi then builds on elegans as `nix-builder` over the ConnectX-7 link,
authenticated by its host key; until both are set, each Spark builds alone.
