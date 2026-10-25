# Hugging Face models pinned by commit, exported read-only to model-sync hosts.
# A model is complete once its `.nixlab-revision` holds the commit.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  root = "/tank/models";
  library = config.homelab.models.library;

  clients = lib.filter (
    name:
    let
      c = inputs.self.nixosConfigurations.${name}.config.homelab;
    in
    c ? models && c.models ? source && c.models.source.host == config.homelab.nodes.albipes.ip
  ) (lib.attrNames inputs.self.nixosConfigurations);

  sync = pkgs.writeShellApplication {
    name = "model-library-sync";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.python3Packages.huggingface-hub
      pkgs.python3Packages.hf-xet
    ];
    text = ''
      library='${builtins.toJSON library}'
      root=${root}

      # The item may still hold a placeholder, and a bad token fails even
      # public downloads.
      token=/var/lib/opnix/secrets/huggingfaceToken
      if [ -r "$token" ] && grep -q '^hf_' "$token"; then
        export HF_TOKEN_PATH="$token"
      fi

      # Only marked directories, so nothing it did not download is touched.
      find "$root" -mindepth 3 -maxdepth 3 -name .nixlab-revision -printf '%h\n' |
        while read -r dir; do
          repo=''${dir#"$root"/}
          if ! jq -e --arg r "$repo" 'has($r)' <<< "$library" > /dev/null; then
            echo "removing $repo (no longer in the library)"
            rm -rf "$dir"
          fi
        done
      find "$root" -mindepth 1 -maxdepth 1 -type d -empty -delete

      jq -r 'to_entries[] | "\(.key) \(.value.rev)"' <<< "$library" |
        while read -r repo rev; do
          dir="$root/$repo"
          if [ "$(cat "$dir/.nixlab-revision" 2> /dev/null)" = "$rev" ]; then
            continue
          fi
          echo "downloading $repo@$rev"
          rm -f "$dir/.nixlab-revision"
          hf download "$repo" --revision "$rev" --local-dir "$dir"
          printf '%s\n' "$rev" > "$dir/.nixlab-revision"
        done
    '';
  };
in
{
  options.homelab.models.library = mkOption {
    type = types.attrsOf (
      types.submodule {
        options.rev = mkOption {
          type = types.strMatching "[0-9a-f]{40}";
          description = "Hugging Face commit to pin the model to.";
        };
      }
    );
    default = { };
    example = {
      "Qwen/Qwen3-8B".rev = "0000000000000000000000000000000000000000";
    };
    description = "Models to keep on albipes, by Hugging Face repo id.";
  };

  config = {
    homelab.models.library = { };

    users.users.models = {
      isSystemUser = true;
      group = "models";
    };
    users.groups.models = { };
    systemd.tmpfiles.rules = [ "d ${root} 0755 models models -" ];

    # Type=exec: hours-long downloads must not hold up a deploy.
    systemd.services.model-library-sync = {
      description = "Download and prune the model library";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ root ];
      environment = {
        HF_HOME = "/var/cache/model-library";
        HF_HUB_DISABLE_TELEMETRY = "1";
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = lib.getExe sync;
        User = "models";
        Group = "models";
        CacheDirectory = "model-library";
        UMask = "0022";
        Restart = "on-failure";
        RestartSec = "10min";
      };
    };

    homelab.reboot.blockers = [ "model-library-sync.service" ];

    # 1Password item: a Hugging Face read-scope access token in `token`,
    # needed only for gated models.
    services.onepassword-secrets.secrets.huggingfaceToken = {
      reference = "op://homelab/huggingface/token";
      owner = "models";
      group = "models";
      services = [ "model-library-sync" ];
    };

    # Weights are not secret: world-readable, root squashed.
    services.nfs.server = {
      enable = true;
      exports = lib.concatMapStrings (
        name: "${root} ${config.homelab.nodes.${name}.ip}(ro,no_subtree_check,root_squash,crossmnt)\n"
      ) clients;
    };
    services.nfs.settings.nfsd = {
      vers3 = false;
      "vers4.0" = false;
    };
    networking.firewall.allowedTCPPorts = [ 2049 ];
  };
}
