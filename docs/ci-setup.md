# CI/CD one-time setup

Configured outside the repo, once. GitHub verifies and fills a public Cachix
cache: hosts pull `main` and deploy themselves (`modules/comin.nix`), so
nothing in GitHub reaches the lab. Its secrets write only to that cache and,
through the weekly flake.lock PR, to this repository.

## GitHub

1. Create `measlesbagel/nixlab`, public, with pull requests restricted to
   collaborators (Settings > General > Features; UI only).
2. Actions: only GitHub-owned actions plus `DeterminateSystems/*`,
   `gitleaks/*`, `zizmorcore/*`, `cachix/cachix-action@*`, and the actions
   `update-flake-lock` calls, which the list also gates:
   `peter-evans/create-pull-request@*`, `DamianReeves/write-file-action@*`,
   `pedrolamas/handlebars-action@*`, `juliangruber/read-file-action@*` and
   `crazy-max/ghaction-import-gpg@*` (it pins them by SHA). SHA pinning required;
   approval for every outside contributor's run; a read-only default token
   that cannot approve PRs.
3. Ruleset `main`: require a pull request with code-owner review and the
   `Secret scan`, `Workflow lint`, `Flake check`, `Commit format` and
   `Flake lock` status checks; block force pushes and deletion; repository
   admins bypass. (`Build <host>` exists only for changed hosts, so it cannot
   be required by name.) `.github/CODEOWNERS` makes the owner review every PR,
   so agent accounts cannot merge their own. Pull requests merge by squash
   only, with the PR title as the commit subject (Settings > General > Pull
   Requests). This ruleset is the deploy gate: every host applies whatever
   lands on `main`, provided GitHub signed the tip commit
   (`modules/comin.nix`). Merge in the web UI; a commit pushed straight to
   `main`, even by an admin, is not deployed until a signed one lands on top.
4. Secret scanning with push protection, Dependabot alerts and private
   vulnerability reporting.
5. First push: `[skip ci]` in the head commit.

Remote access and SSH logins (WireGuard, Pocket ID, opkssh) are set up
once per [remote-access.md](remote-access.md).

## Cachix cache

Hosts and CI substitute from [measlesbagel.cachix.org](https://measlesbagel.cachix.org),
a public cache. `modules/cache.nix` owns its name and public key and adds them
to `nix.settings`, after cache.nixos.org. The Sparks also take
graham33.cachix.org (`modules/spark.nix`), where upstream's full builds push
the NVIDIA kernel, and cache.flox.dev for CUDA, which upstream's module adds.
They take their kernel package set, driver included, from nixos-dgx-spark's
own nixpkgs, so it stays the one upstream builds while our nixpkgs moves on.
CI's build job substitutes from each host's `nix.settings.extra-substituters`,
so it downloads what that host would.

### CI push

Once, by hand:

1. In the cache's settings on app.cachix.org, create an auth token that can
   write to it.
2. Add it as the repo secret `CACHIX_AUTH_TOKEN` (Settings > Secrets and
   variables > Actions).

Until then CI builds as before, logs that it has no token and pushes nothing.

How the push works:

- The build job starts cachix-action before it builds. The action registers a
  Nix post-build hook that queues what that job builds, and uploads the queue
  when the job ends. Nix runs the hook for builds only, never for
  substitutions.
- Cachix uploads the whole closure of each queued path, minus what the cache or
  its upstream caches already have. A path substituted from Flox or graham33
  would therefore go up with any path that uses it. The `Plan Cachix push` step
  turns the push on only when every host of the job substitutes from
  cache.nixos.org and this cache alone. Today that pushes the x86_64 hosts and
  skips the Sparks.
- Upstream caches (the cache's settings): keep cache.nixos.org, which is the
  default. Cachix skips any path in a listed upstream, so every host must
  substitute from each upstream listed, or it builds a skipped path itself.
  graham33.cachix.org qualifies because the Sparks use it. Add another, such
  as nix-community, only together with a host substituter. cache.flox.dev is
  not a Cachix cache, so it cannot be listed.
- Only same-repo PRs get the token. A fork or Dependabot PR gets an empty one,
  and the action then pushes nothing and does not fail. Nix builds run in a
  sandbox and cannot read the token, but the action writes it to the runner's
  `~/.config/cachix/cachix.dhall`. Any step of that job can read it, and so can
  anyone who can push a branch here. It writes to this cache only; revoke it in
  the cache's settings if in doubt.
- The first run with a token must not log that the user is "not allowed to set
  the post-build-hook". The action then falls back to scanning the store, which
  also uploads substituted paths.
- The free tier holds 5 GB and evicts the least recently used paths.

## Remote builder (leetzi → elegans)

Once both Sparks are provisioned, commit each one's
`/etc/ssh/ssh_host_ed25519_key.pub` as `sshHostKey` in `modules/topology.nix`.
leetzi then builds on elegans as `nix-builder` over the ConnectX-7 link,
authenticated by its host key, so the Spark kernel compiles once. Until both
are set, each Spark builds alone.

## Flake lock updates

`.github/workflows/update-flake-lock.yml` runs `nix flake update` every
Monday at 09:17 UTC and opens one PR, `chore(flake): update flake.lock`,
from the branch `update_flake_lock_action`. A later run updates that same PR.
Dependabot only bumps GitHub Actions (`.github/dependabot.yml`).

The PR is opened with a personal access token, because GitHub starts no
workflows for a PR that `GITHUB_TOKEN` opens, so CI would never run on it.
It therefore shows as opened by measlesbagel, runs the full CI like any PR,
and its commit is authored by `github-actions[bot]`. After review, merge it in
the web UI. That deploys like any other merge, because comin only deploys tips
that GitHub signed.

Before the first run, create a fine-grained token with resource owner
measlesbagel, only the `nixlab` repository, Contents and Pull requests read
and write, and no expiration, and add it as the Actions secret
`FLAKE_UPDATE_TOKEN`.

Schedules and manual runs use the workflow on `main`, so nothing runs before
it merges. After the merge and the token, trigger the first run with:

```console
gh workflow run update-flake-lock.yml
```
