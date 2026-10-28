{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.cache;
in
{
  # The public Cachix cache that CI fills (docs/ci-setup.md).
  options.homelab.cache = {
    name = mkOption {
      type = types.str;
      default = "measlesbagel";
    };
    publicKey = mkOption {
      type = types.str;
      default = "measlesbagel.cachix.org-1:pDkALnrF/24OQ8Q0ALzdcKqVfOb7zsbizkp77m4RwBE=";
    };
  };

  config.nix.settings = {
    extra-substituters = [ "https://${cfg.name}.cachix.org" ];
    extra-trusted-public-keys = [ cfg.publicKey ];
    # A down cache must not stall a deploy.
    connect-timeout = 5;
  };
}
