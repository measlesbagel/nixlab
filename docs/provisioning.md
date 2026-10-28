# Provisioning a host

`nix run .#provision -- <host>` kexecs the machine's current OS into an
installer that keeps its LAN address, installs the host with nixos-anywhere,
and waits for `deploy@<ip>` to come back with the host key it was given.

```console
# first install, taking over the machine's current OS (bootstrapTarget)
nix run .#provision -- seladonia --bootstrap

# reinstall a host that already runs NixOS
nix run .#provision -- seladonia

# build the installer and print the steps without touching anything
nix run .#provision -- seladonia --bootstrap --dry-run
```

Run it from chilense, signed in to the 1Password CLI with access to the
`private` vault. A reinstall logs in as `deploy@<ip>`, so the break-glass key
(or an opkssh login) must be in your agent; see
[remote-access.md](remote-access.md). CI never provisions: old
OSes are only reachable on the LAN, and an install wipes disks.

It reads `nixlab-opnix/credential` from `private`: the token of the
read-only service account every host shares on the `homelab` vault,
installed at `/etc/opnix-token`. Override with `OPNIX_TOKEN` or
`OPNIX_TOKEN_REF`.

It also makes the host's SSH host key and prints the `sshHostKey` line to
commit in `modules/topology.nix`.

Nothing secret reaches a disk or the store: the host key and token stay in a
private directory under `$XDG_RUNTIME_DIR` (tmpfs), deleted on exit.

## Requirements on the target

- **Secure Boot off:** a lockdown kernel refuses to kexec an unsigned kernel,
  and the installed system boots unsigned systemd-boot.
- **≥ 2.5 GB RAM**: the installer runs from memory.
- **First install only:** the `bootstrapTarget` in `modules/topology.nix` must
  accept your SSH key and become root without a password (root itself, or a
  user with passwordless `sudo`).

## albipes and chilense: data first

Provisioning albipes formats its data drives, and the UGOS data's only
other copy is on chilense, whose provisioning formats that disk. Follow
[nas-migration.md](nas-migration.md).

## The Sparks (leetzi, elegans)

- **Secure Boot is on from the factory:** switch it off in the BIOS (keyboard
  and monitor; the GX10 has no BMC). DGX OS still boots with it off.
- **Update firmware from DGX OS first** (`fwupdmgr update`): factory
  firmware only boots DGX OS.
- **Your SSH key on root**, the bootstrapTarget. DGX OS allows only key logins
  for root, so add it through `sparkrun`:
  `ssh -t sparkrun@<ip> "sudo install -d -m 700 /root/.ssh && echo '<public key>' | sudo tee -a /root/.ssh/authorized_keys >/dev/null"`.
- **An aarch64 builder for the installer:** QEMU emulation is enough
  (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on NixOS,
  `extra-platforms` plus qemu-user binfmt elsewhere). The first build takes
  about an hour; it is reused until nixpkgs changes.
- **The system builds on the Spark** (`--build-on remote`). The NVIDIA kernel
  comes from graham33.cachix.org when upstream has built it for our nixpkgs;
  otherwise the Spark compiles it, in about half an hour.
- **The installer's stock kernel may not get Ethernet** on the RTL8127
  (mainline `r8169`). If it never comes back on its address, fall back to
  a USB install; keep a DGX OS recovery USB to hand either way.
- Do elegans first; leetzi stays on DGX OS until elegans checks out.

## Reinstalls

A reinstall gets a new host key: commit the `sshHostKey` that `provision`
prints, or deploys and the other hosts refuse it.
