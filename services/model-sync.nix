# Local copies of library models, from albipes or a peer. `.nixlab-revision`
# is copied last; consumers should wait for it.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.homelab.models;
  local = "/var/lib/models";
  mount = "/run/model-source";
  library = inputs.self.nixosConfigurations.albipes.config.homelab.models.library;

  sync = pkgs.writeShellApplication {
    name = "model-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.rsync
    ];
    text = ''
      models=(${lib.escapeShellArgs cfg.local})

      # Prune first: two large models do not fit side by side.
      find ${local} -mindepth 3 -maxdepth 3 -name .nixlab-revision -printf '%h\n' |
        while read -r dir; do
          repo=''${dir#${local}/}
          keep=0
          for m in "''${models[@]}"; do [ "$m" = "$repo" ] && keep=1; done
          if [ "$keep" = 0 ]; then
            echo "removing $repo"
            rm -rf "$dir"
          fi
        done
      find ${local} -mindepth 1 -maxdepth 1 -type d -empty -delete

      pending=0
      for repo in "''${models[@]}"; do
        src="${mount}/$repo"
        dst="${local}/$repo"
        want=$(cat "$src/.nixlab-revision" 2> /dev/null || true)
        if [ -z "$want" ]; then
          echo "$repo is not complete at the source yet"
          pending=1
          continue
        fi
        if [ "$(cat "$dst/.nixlab-revision" 2> /dev/null)" = "$want" ]; then
          continue
        fi
        echo "copying $repo@$want"
        rm -f "$dst/.nixlab-revision"
        mkdir -p "$dst"
        # --inplace: no temporary second copy of multi-GB shards.
        rsync -a --delete --inplace --partial \
          --exclude .nixlab-revision --exclude .cache "$src/" "$dst/"
        cp "$src/.nixlab-revision" "$dst/.nixlab-revision"
      done

      # Non-zero makes systemd retry until every model has arrived.
      exit "$pending"
    '';
  };
in
{
  options.homelab.models = {
    local = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Library models (Hugging Face repo ids) to keep a local copy of.";
    };
    source = {
      host = mkOption {
        type = types.str;
        default = config.homelab.nodes.albipes.ip;
        description = "NFS server to copy from: albipes, or a peer's serveTo.";
      };
      path = mkOption {
        type = types.str;
        default = "/tank/models";
      };
    };
    serveTo = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            interface = mkOption { type = types.str; };
            clients = mkOption { type = types.listOf types.str; };
          };
        }
      );
      default = null;
      description = "Re-export the local copies read-only to peers on one interface.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = lib.all (m: library ? ${m}) cfg.local;
          message = "homelab.models.local lists models missing from the library: ${
            toString (lib.filter (m: !(library ? ${m})) cfg.local)
          }";
        }
      ];

      systemd.tmpfiles.rules = [ "d ${local} 0755 root root -" ];

      fileSystems.${mount} = {
        device = "${cfg.source.host}:${cfg.source.path}";
        fsType = "nfs";
        options = [
          "ro"
          "x-systemd.automount"
          "x-systemd.idle-timeout=10min"
          "noauto"
          "nofail"
          "nconnect=8"
          "rsize=1048576"
        ];
      };

      # Type=exec: long copies must not hold up a deploy.
      systemd.services.model-sync = {
        description = "Copy listed models from the library and prune the rest";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.RequiresMountsFor = [ local ];
        serviceConfig = {
          Type = "exec";
          ExecStart = lib.getExe sync;
          Restart = "on-failure";
          RestartSec = "5min";
        };
      };

      homelab.reboot.blockers = [ "model-sync.service" ];
    }

    (lib.mkIf (cfg.serveTo != null) {
      services.nfs.server = {
        enable = true;
        exports = lib.concatMapStrings (
          ip: "${local} ${ip}(ro,no_subtree_check,root_squash)\n"
        ) cfg.serveTo.clients;
      };
      services.nfs.settings.nfsd = {
        vers3 = false;
        "vers4.0" = false;
      };
      networking.firewall.interfaces.${cfg.serveTo.interface}.allowedTCPPorts = [ 2049 ];
    })
  ];
}
