{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.homelab = {
    domain = mkOption {
      type = types.str;
      default = "measlesbagel.dev";
    };
    nodes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            ip = mkOption { type = types.str; };
            tailscaleName = mkOption { type = types.str; };
            tailscaleTags = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "ACL tags the node advertises; owned in tailscale/policy.hujson.";
            };
            bootstrapTarget = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                SSH target on the machine's pre-NixOS OS, used once by
                `provision --bootstrap`. Reinstalls go through deploy@<host>.
              '';
            };
            roles = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            os = mkOption {
              type = types.str;
              default = "nixos";
            };
          };
        }
      );
      default = { };
    };
  };

  config.homelab.nodes = {
    seladonia = {
      ip = "192.168.4.39";
      tailscaleName = "seladonia";
      tailscaleTags = [ "tag:typhochlaena" ];
      bootstrapTarget = "root@192.168.4.39"; # Proxmox
      roles = [
        "edge"
        "services"
      ];
    };
    albipes = {
      ip = "192.168.4.41";
      tailscaleName = "albipes";
      tailscaleTags = [ "tag:hapalotremus" ];
      bootstrapTarget = "root@192.168.4.41"; # UGOS, root SSH enabled for provisioning
      roles = [
        "storage"
        "backup"
        "ups-server"
      ];
    };
    chilense = {
      ip = "192.168.4.21";
      tailscaleName = "chilense";
      tailscaleTags = [ "tag:homoeomma" ];
      roles = [ "desktop" ];
    };

    leetzi = {
      ip = "192.168.4.51";
      tailscaleName = "leetzi";
      tailscaleTags = [ "tag:cyriocosmus" ];
      # DGX OS; root takes keys only, added via sparkrun's sudo.
      bootstrapTarget = "root@192.168.4.51";
      roles = [
        "gpu"
        "inference"
      ];
    };
    elegans = {
      ip = "192.168.4.50";
      tailscaleName = "elegans";
      tailscaleTags = [ "tag:cyriocosmus" ];
      # DGX OS; root takes keys only, added via sparkrun's sudo.
      bootstrapTarget = "root@192.168.4.50";
      roles = [
        "gpu"
        "inference"
      ];
    };
  };
}
