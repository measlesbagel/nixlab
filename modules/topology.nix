{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.homelab) nodes;
in
{
  options.homelab = {
    addressesOf = mkOption {
      type = types.functionTo (types.listOf types.str);
      readOnly = true;
      default =
        source:
        if nodes ? ${source} then
          [ nodes.${source}.ip ]
        else
          let
            members = lib.filterAttrs (_: node: node.genus == source) nodes;
          in
          if members != { } then lib.mapAttrsToList (_: node: node.ip) members else [ source ];
      description = "The addresses a host name, genus or literal address or CIDR stands for.";
    };
    domain = mkOption {
      type = types.str;
      default = "measlesbagel.dev";
    };
    lan.subnet = mkOption {
      type = types.str;
      default = "192.168.4.0/24";
    };
    lan.domain = mkOption {
      type = types.str;
      default = "lab.${config.homelab.domain}";
      description = "Hosts answer as <name> and <name>.<this>, on the hosts and over WireGuard.";
    };
    breakGlassKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Public half of the break-glass SSH key in 1Password, for when Pocket ID
        or seladonia is down. Accepted for measles and deploy from the LAN only.
      '';
    };
    wireguard = {
      endpoint = mkOption {
        type = types.str;
        default = "seladonia";
        description = "The one host that terminates WireGuard; the router forwards its port here.";
      };
      subnet = mkOption {
        type = types.str;
        default = "10.100.0.0/24";
      };
      address = mkOption {
        type = types.str;
        default = "10.100.0.1";
        description = "The endpoint's address in the subnet.";
      };
      port = mkOption {
        type = types.port;
        default = 51820;
      };
      publicKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The endpoint's public key, generated on its first boot (`wg show wg0 public-key`).";
      };
      peers = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              ip = mkOption { type = types.str; };
              publicKey = mkOption { type = types.str; };
            };
          }
        );
        default = { };
        description = "Remote-access devices. Each makes its own key; every peer is an admin.";
      };
    };
    nodes = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            ip = mkOption { type = types.str; };
            genus = mkOption {
              type = types.str;
              description = "The role, named for the host's tarantula genus (docs/taxonomy.md); also a host group.";
            };
            sshHostKey = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                The host's `/etc/ssh/ssh_host_ed25519_key.pub` line, once it
                is provisioned. Public by design.
              '';
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
      genus = "typhochlaena";
      ip = "192.168.4.39";
      bootstrapTarget = "root@192.168.4.39"; # Proxmox
      roles = [
        "edge"
        "services"
      ];
    };
    albipes = {
      genus = "hapalotremus";
      ip = "192.168.4.41";
      bootstrapTarget = "root@192.168.4.41"; # UGOS, root SSH enabled for provisioning
      roles = [
        "storage"
        "backup"
        "ups-server"
      ];
    };
    chilense = {
      genus = "homoeomma";
      ip = "192.168.4.21";
      roles = [ "desktop" ];
    };

    leetzi = {
      genus = "cyriocosmus";
      ip = "192.168.4.51";
      # DGX OS; root takes keys only, added via sparkrun's sudo.
      bootstrapTarget = "root@192.168.4.51";
      roles = [
        "gpu"
        "inference"
      ];
    };
    elegans = {
      genus = "cyriocosmus";
      ip = "192.168.4.50";
      # DGX OS; root takes keys only, added via sparkrun's sudo.
      bootstrapTarget = "root@192.168.4.50";
      roles = [
        "gpu"
        "inference"
      ];
    };
  };
}
