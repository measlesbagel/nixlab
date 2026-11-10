# Source side of albipes's btrbk pulls, over the LAN with albipes's own key.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.homelab.replication) pullKey;
  subvolumes = config.homelab.replicate;
in
{
  options.homelab = {
    replicate = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        Subvolumes albipes pulls, as keys of `homelab.snapshots` with class
        `state`; keep secrets out of these.
      '';
    };
    replication.pullKey = mkOption {
      type = types.nullOr types.str;
      # Set once albipes has made it (docs/remote-access.md).
      default = null;
      description = "albipes's btrbk public key, /var/lib/btrbk/.ssh/id_ed25519.pub.";
    };
  };

  config = lib.mkIf (subvolumes != [ ]) {
    assertions = map (s: {
      assertion = (config.homelab.snapshots.${s} or null) == "state";
      message = "homelab.replicate: ${s} needs homelab.snapshots.\"${s}\" = \"state\"; albipes only sends existing snapshots.";
    }) subvolumes;

    # Pulls need only to read and send snapshots; albipes never creates or
    # deletes anything here.
    services.btrbk.sshAccess = lib.optional (pullKey != null) {
      key = pullKey;
      roles = [
        "info"
        "send"
      ];
    };

    homelab.ssh.logins.btrbk = [ "hapalotremus" ];
  };
}
