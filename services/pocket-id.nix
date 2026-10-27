# The OIDC provider opkssh logs people in with (modules/ssh.nix). Public like
# every vhost, so phones can log in from outside; it only takes passkeys.
{ config, ... }:
let
  host = "id.${config.homelab.domain}";
  port = 1411;
in
{
  services.pocket-id = {
    enable = true;
    settings = {
      APP_URL = "https://${host}";
      TRUST_PROXY = true;
      ANALYTICS_DISABLED = true;
      HOST = "127.0.0.1";
      PORT = port;
    };
    credentials.ENCRYPTION_KEY = "/var/lib/opnix/secrets/pocketIdEncryptionKey";
  };

  # 1Password item: at least 16 random bytes, e.g. `openssl rand -base64 32`.
  # Losing it makes the database unreadable.
  services.onepassword-secrets.secrets.pocketIdEncryptionKey = {
    reference = "op://homelab/pocket-id/encryption-key";
    services = [ "pocket-id" ];
  };

  services.caddy.virtualHosts.${host}.extraConfig = ''
    reverse_proxy localhost:${toString port}
  '';

  # Losing users and passkeys leaves only the break-glass key.
  homelab.backup.paths = [ config.services.pocket-id.dataDir ];
}
