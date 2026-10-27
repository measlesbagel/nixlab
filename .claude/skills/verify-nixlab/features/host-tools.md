# Host-side tools

These are the flake apps an operator runs on chilense: `changed-hosts` (which
hosts a commit range rebuilds; CI uses it to pick builds) and
`provision --dry-run` (builds the installer and prints the install plan). They
run on this machine, not in the VM.

## Sub-features

- `changed-hosts-none`: a base equal to HEAD prints `[]`.
- `changed-hosts-diff`: a base before a host-touching commit lists exactly the hosts whose toplevel changed, with their systems.
- `provision-dry`: `provision <host> --dry-run` builds the kexec installer and prints the `nixos-anywhere` command without connecting anywhere.

## How to get to it (user POV)

- `nix run .#changed-hosts -- <base-rev>`
- `nix run .#provision -- <host> [--bootstrap] --dry-run`

## Driving it with nixlab-vm

Preconditions:

- A run is exported so the transcript has somewhere to go. You do not need to
  launch a VM for this feature alone, but `host` requires a run directory, so
  use an existing one.

Steps:

- **No change.** Run `nixlab-vm host -- nix run .#changed-hosts -- HEAD`. It
  exits 0, and stdout is `[]`.
- **Real diff.** Pick a commit that changed one host, then run
  `nixlab-vm host -- nix run .#changed-hosts -- <that-commit>~1`. stdout lists
  that host with its `system`.
- **Dry-run provision.** Run `nixlab-vm host -- nix run .#provision -- seladonia --bootstrap --dry-run`.
  It exits 0 and prints `+ nixos-anywhere --flake …#seladonia … --target-host root@192.168.4.39`
  and a throwaway `sshHostKey` line. It also prints `>> seladonia is up`,
  even though nothing was contacted.

## Gotchas

- `changed-hosts` compares committed trees only, so uncommitted edits never
  show up. Commit first, or don't treat its output as proof for a dirty tree.
- `--dry-run` does not call `op`, and it connects to no lab host. It still
  uses the network to fetch the installer's substitutes. It also generates a
  host key in `$XDG_RUNTIME_DIR` that it then throws away. Never commit the
  `sshHostKey` it prints.
- Never drop `--dry-run`. Without it the command wipes the target's disks.
