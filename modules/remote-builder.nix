# One host builds for another over a direct link, so a derivation both need
# (the Spark kernel) compiles once: the client's build runs in the builder's
# store, where Nix locks an output path while it builds. Off until both
# hosts' sshHostKey is in modules/topology.nix.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.builder;
  inherit (config.homelab) nodes;
  user = "nix-builder";
in
{
  options.homelab.builder = {
    serveTo = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            interface = mkOption {
              type = types.str;
              description = "The link clients reach this host on; SSH opens only there.";
            };
            clients = mkOption {
              type = types.attrsOf types.str;
              description = "Client nodes and their addresses on that link.";
            };
          };
        }
      );
      default = null;
    };
    remote = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            host = mkOption {
              type = types.str;
              description = "The node that builds for this one.";
            };
            address = mkOption {
              type = types.str;
              description = "Its address on the link.";
            };
          };
        }
      );
      default = null;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.serveTo != null) {
      users.users.${user} = {
        isSystemUser = true;
        group = user;
        # The forced command runs through the login shell.
        useDefaultShell = true;
        openssh.authorizedKeys.keys = lib.mapAttrsToList (
          name: address:
          ''restrict,command="nix-daemon --stdio",from="${address}" ${nodes.${name}.sshHostKey}''
        ) (lib.filterAttrs (name: _: nodes.${name}.sshHostKey != null) cfg.serveTo.clients);
      };
      users.groups.${user} = { };
      # Clients send derivations, which only trusted users may build.
      nix.settings.trusted-users = [ user ];
      networking.firewall.interfaces.${cfg.serveTo.interface}.allowedTCPPorts = [ 22 ];
      homelab.ssh.logins.${user} = lib.attrValues cfg.serveTo.clients;
    })

    (lib.mkIf (cfg.remote != null && nodes.${cfg.remote.host}.sshHostKey != null) {
      nix.distributedBuilds = true;
      nix.settings.builders-use-substitutes = true;
      nix.buildMachines = [
        {
          hostName = cfg.remote.address;
          protocol = "ssh-ng";
          sshUser = user;
          # nix-daemon connects as root, which can read it.
          sshKey = "/etc/ssh/ssh_host_ed25519_key";
          inherit (pkgs.stdenv.hostPlatform) system;
          maxJobs = 4;
          supportedFeatures = [
            "big-parallel"
            "benchmark"
            "nixos-test"
          ];
        }
      ];
      programs.ssh.knownHosts."${cfg.remote.host}-builder" = {
        hostNames = [ cfg.remote.address ];
        publicKey = nodes.${cfg.remote.host}.sshHostKey;
      };
    })
  ];
}
