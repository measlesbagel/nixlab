{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.cache;
  endpoint = "http://${config.homelab.nodes.albipes.ip}:${toString cfg.port}";
in
{
  options.homelab.cache = {
    name = mkOption {
      type = types.str;
      default = "nixlab";
    };
    port = mkOption {
      type = types.port;
      default = 7313;
    };
    publicUrl = mkOption {
      type = types.str;
      readOnly = true;
      default = "https://cache.${config.homelab.domain}/${cfg.name}";
      description = "Read-only route for CI (services/attic-public.nix).";
    };
    publicKey = mkOption {
      type = types.nullOr types.str;
      # Set once albipes has first booted (docs/ci-setup.md); until then
      # hosts neither pull from nor push to it.
      default = null;
      description = "Public signing key of the cache, as printed by `attic cache info`.";
    };
  };

  config = lib.mkIf (cfg.publicKey != null) {
    nix.settings = {
      substituters = [ "${endpoint}/${cfg.name}" ];
      trusted-public-keys = [ cfg.publicKey ];
      # A down cache must not stall a deploy.
      connect-timeout = 5;
    };

    # Hosts fill the cache with what they build; attic skips paths that
    # cache.nixos.org already signs. A token that can push can poison what
    # every host substitutes, so it never leaves the lab (no CI writes).
    systemd.services.attic-push = {
      description = "Push locally built store paths to the lab cache";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # attic reads the token file itself, so it never appears in argv.
      environment.XDG_CONFIG_HOME = pkgs.writeTextDir "attic/config.toml" ''
        default-server = "lab"
        [servers.lab]
        endpoint = "${endpoint}"
        token-file = "/run/credentials/attic-push.service/token"
      '';
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.attic-client "attic"} watch-store lab:${cfg.name}";
        DynamicUser = true;
        LoadCredential = "token:/var/lib/opnix/secrets/atticPushToken";
        Restart = "always";
        RestartSec = 30;
      };
    };

    # 1Password item: an atticd token made with
    # `atticd-atticadm make-token --sub hosts --validity 1y --push nixlab --pull nixlab`.
    services.onepassword-secrets.secrets.atticPushToken = {
      reference = "op://homelab/attic-push/token";
      services = [ "attic-push" ];
    };
  };
}
