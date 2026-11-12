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

    # Runs the key's forced command as sshd would, with what btrbk on albipes
    # sends in SSH_ORIGINAL_COMMAND. stdout would be the send stream.
    homelab.vmTest.checks.replication =
      let
        subvolume = lib.head subvolumes;
        top = dirOf subvolume;
      in
      ''
        with subtest("the pull key sends replicated snapshots and nothing else"):
            machine.succeed("systemctl start btrbk-state.service")
            snapshot = machine.succeed("ls -d ${top}/${snapshotDir}/${baseNameOf subvolume}.*").split()[0]
            pull_filter = ${builtins.toJSON filter}

            def pull(command: str) -> tuple[int, str]:
                return machine.execute(f"runuser -u btrbk -- env {quote('SSH_ORIGINAL_COMMAND=' + command)} sh -c {quote(pull_filter)} 2>&1 > /dev/null")

            for command in ["sudo -n readlink -e '${subvolume}'", f"sudo -n btrfs send '{snapshot}'"]:
                status, output = pull(command)
                assert status == 0, f"{command}: {output}"
            for command in [
                "sudo -n btrfs send '${top}/@snapshots/@other.20260101T0000'",
                f"sudo -n btrfs subvolume delete '{snapshot}'",
                "sudo -n btrfs subvolume snapshot -r '${subvolume}' '${top}/${snapshotDir}/@new'",
            ]:
                status, output = pull(command)
                assert status == 255 and "ssh command rejected" in output, f"{command}: {status} {output}"
      '';
  };
}
