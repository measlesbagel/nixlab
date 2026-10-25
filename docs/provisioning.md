# Provisioning a host

`nix run .#provision -- <host>` kexecs the machine's current OS into an
installer that joins the tailnet as `<host>-installer`, installs the host
with nixos-anywhere, and waits for `deploy@<host>` to come back.

```console
# first install, taking over the machine's current OS (bootstrapTarget)
nix run .#provision -- seladonia --bootstrap

# reinstall a host that already runs NixOS
nix run .#provision -- seladonia

# build the installer and print the steps without touching anything
nix run .#provision -- seladonia --bootstrap --dry-run
```

Run it from an admin machine (chilense) on the tailnet, signed in to the
1Password CLI with access to the `private` vault. CI never provisions: old
OSes are only reachable on the LAN, and an install wipes disks.

It reads two items from `private`:

- `nixlab-opnix/credential`: the token of the read-only service account every
  host shares on the `homelab` vault, installed at `/etc/opnix-token`.
  Override with `OPNIX_TOKEN` or `OPNIX_TOKEN_REF`.
- `tailscale-provision/{client-id,client-secret}`: the provisioning OAuth
  client ([ci-setup.md](ci-setup.md#tailscale)). It mints two single-use keys
  that expire in a day: an ephemeral one for the installer (`tag:instar`)
  and one with the host's tags. Pass `TS_INSTALLER_AUTHKEY` /
  `TS_HOST_AUTHKEY` to use keys made by hand instead.

Nothing secret reaches a disk or the store: the keys and token stay in a
private directory under `$XDG_RUNTIME_DIR` (tmpfs), deleted on exit; each join
key is deleted once it has joined; the OAuth client secret never leaves the
machine running provision.

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
- **The system builds on the Spark** (`--build-on remote`, about half an
  hour): the NVIDIA kernel is in no public cache. Later deploys come from the
  lab cache.
- **The installer's stock kernel may not get Ethernet** on the RTL8127
  (mainline `r8169`). If it never joins the tailnet, fall back to a USB
  install; keep a DGX OS recovery USB to hand either way.
- Do elegans first; leetzi stays on DGX OS until elegans checks out.

## Reinstalls

Remove the old machine in the Tailscale admin console first, or the
reinstalled host joins as `<name>-1`.
