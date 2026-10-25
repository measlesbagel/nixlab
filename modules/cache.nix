{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.cache;
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
    publicKey = mkOption {
      type = types.nullOr types.str;
      # Set once albipes has first booted (docs/ci-setup.md); until then
      # deploys copy every path from the deployer.
      default = null;
      description = "Public signing key of the cache, as printed by `attic cache info`.";
    };
  };

  config.nix.settings = lib.mkIf (cfg.publicKey != null) {
    substituters = [ "http://${config.homelab.nodes.albipes.ip}:${toString cfg.port}/${cfg.name}" ];
    trusted-public-keys = [ cfg.publicKey ];
    # A down cache must not stall a deploy.
    connect-timeout = 5;
  };
}
