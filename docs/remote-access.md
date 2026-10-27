# Remote access and SSH

How you reach the lab without Tailscale. Tailscale keeps running until all
of this is set up and tested; it is removed in a later change.

- **Transport:** one WireGuard endpoint on seladonia (`services/wireguard.nix`)
  at `vpn.measlesbagel.dev`, UDP 51820. Peers are your own devices, listed in
  `homelab.wireguard.peers` (`modules/topology.nix`). Every peer is an admin
  and reaches every port on every host, as on the tailnet.
- **Login:** OpenSSH with [opkssh](https://github.com/openpubkey/opkssh):
  `opkssh login` signs you in to Pocket ID (`id.measlesbagel.dev`, on
  seladonia) with your passkey and writes a 24-hour key to `~/.ssh`. Members
  of the Pocket ID group `nixlab-admins` may log in as `measles` and
  `deploy` (`modules/ssh.nix`).
- **Break-glass:** one SSH key in 1Password, accepted for `measles` and
  `deploy` from the LAN only, for when Pocket ID or seladonia is down.
  opkssh fetches Pocket ID's keys on every login, so it does not work while
  Pocket ID is down.
- **Who may log in from where:** sshd's `AllowUsers` lists user@source pairs
  (`homelab.ssh.logins`), and nftables opens port 22 to exactly those
  sources. Everything else on the LAN (phones, IoT, guests) gets nothing.
  `tests/access-policy.nix` checks it in `nix flake check`.

| User | From | Hosts |
| --- | --- | --- |
| `measles`, `deploy` | WireGuard peers, chilense | all |
| `syncoid` | albipes | seladonia, chilense |
| `nix-builder` | leetzi, on the Spark link | elegans |

## One-time setup

Do these in order; each step is safe to merge on its own.

1. **Break-glass key.** Create an SSH key in 1Password (e.g. `nixlab
   break-glass` in `private`), and commit its public key as
   `homelab.breakGlassKey` in `modules/topology.nix`. After the deploy,
   `ssh deploy@192.168.4.39` from chilense works with the 1Password agent.
2. **Pocket ID.** Create `op://homelab/pocket-id/encryption-key` (e.g.
   `openssl rand -base64 32`) before the deploy that adds Pocket ID. Then, on
   the LAN:
   - Open `https://id.measlesbagel.dev/setup`, create your account and
     register a passkey.
   - Create the group `nixlab-admins` and add yourself.
   - Create an OIDC client `opkssh`: public client, PKCE on, callback URLs
     `http://localhost:3000/login-callback`,
     `http://localhost:10001/login-callback` and
     `http://localhost:11110/login-callback`.
   - Commit its client ID as `homelab.ssh.pocketId.clientId` in
     `modules/ssh.nix`. It is public by design.
3. **opkssh client** on each device you log in from:

   ```console
   opkssh login --provider "https://id.measlesbagel.dev,<client-id>,,openid profile email groups"
   ssh deploy@192.168.4.39
   ```

   `opkssh login --create-config` writes `~/.opk/config.yml`, where you can
   save the provider and make it the default.
4. **WireGuard.** After seladonia's first deploy with it, read its key with
   `sudo wg show wg0 public-key` and commit it as
   `homelab.wireguard.publicKey`. On the router, forward UDP 51820 to
   192.168.4.39. For each device, generate a key on the device and add it:

   ```nix
   homelab.wireguard.peers.phone = {
     ip = "10.100.0.2";
     publicKey = "<the device's public key>";
   };
   ```

   The device's config:

   ```ini
   [Interface]
   PrivateKey = <made on the device>
   Address = 10.100.0.2/32

   [Peer]
   PublicKey = <homelab.wireguard.publicKey>
   Endpoint = vpn.measlesbagel.dev:51820
   AllowedIPs = 10.100.0.0/24, 192.168.4.0/24
   ```

   Lab hosts route `10.100.0.0/24` back through seladonia themselves
   (`modules/lan.nix`); other LAN devices see seladonia's address.
5. **syncoid.** albipes makes its own key on the next deploy. Commit
   `ssh deploy@192.168.4.41 cat /var/lib/syncoid/.ssh/id_ed25519.pub` as
   `homelab.zfs.pullKey` in `modules/replication.nix`; replication then moves
   from Tailscale SSH to the LAN.
6. **Host keys.** Commit each host's `/etc/ssh/ssh_host_ed25519_key.pub` as
   its `sshHostKey`, so hosts and deploys check it. `provision` prints it
   for new installs.

Pocket ID's data (`/var/lib/pocket-id`) goes to the nightly restic backup.
If it is lost, set it up again from step 2; the client ID changes.
