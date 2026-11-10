# Source side of albipes's btrbk pulls, over the LAN with albipes's own key.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.homelab.replication) pullKey;
  inherit (config.homelab.replication) snapshotDir;
  subvolumes = config.homelab.replicate;
  albipes = config.homelab.nodes.albipes.ip;

  # btrbk resolves each subvolume with readlink before it sends from the
  # snapshot directory; nothing else on the filesystem is reachable.
  allowed = subvolumes ++ lib.unique (map (s: "${dirOf s}/${snapshotDir}") subvolumes);
  filter = lib.concatStringsSep " " (
    [
      "${pkgs.btrbk}/share/btrbk/scripts/ssh_filter_btrbk.sh"
      "--sudo"
      "--info"
      "--send"
    ]
    ++ map (p: "--restrict-path ${lib.escapeShellArg p}") allowed
  );
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
    replication.snapshotDir = mkOption {
      type = types.str;
      default = "@snapshots/replicated";
      readOnly = true;
      description = ''
        Where replicated subvolumes keep their snapshots, relative to the
        top-level mount. Apart from them, the pull key can read only this.
      '';
    };
  };

  config = lib.mkIf (subvolumes != [ ]) {
    assertions = map (s: {
      assertion = (config.homelab.snapshots.${s} or null) == "state";
      message = "homelab.replicate: ${s} needs homelab.snapshots.\"${s}\" = \"state\"; albipes only sends existing snapshots.";
    }) subvolumes;

    # Pulls need only to read and send snapshots; albipes never creates or
    # deletes anything here. Written out instead of services.btrbk.sshAccess,
    # which cannot add `from` or `restrict`.
    users.users.btrbk.openssh.authorizedKeys.keys = lib.optional (
      pullKey != null
    ) ''from="${albipes}",restrict,command="${filter}" ${pullKey}'';

    systemd.tmpfiles.rules = lib.unique (
      map (s: "d ${dirOf s}/${snapshotDir} 0755 root root -") subvolumes
    );

    homelab.ssh.logins.btrbk = [ "hapalotremus" ];
  };
}
