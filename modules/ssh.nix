# OpenSSH logins: opkssh against Pocket ID for people, the 1Password
# break-glass key from the LAN, and an AllowUsers list of user@source pairs
# that nftables mirrors on port 22.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.homelab)
    domain
    lan
    breakGlassKey
    wireguard
    nodes
    addressesOf
    ;
  cfg = config.homelab.ssh;
  issuer = "https://id.${domain}";
  admins = [
    wireguard.subnet
    "homoeomma"
  ];
  addresses = sources: lib.unique (lib.concatMap addressesOf sources);
  people = [
    "measles"
    "deploy"
  ];
in
{
  options.homelab.ssh = {
    logins = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
      description = "Users sshd lets in, by the hosts, genera, addresses or CIDRs they may come from.";
    };
    pocketId = {
      clientId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Pocket ID's public OIDC client for opkssh (docs/remote-access.md).
          Until it is set, only the break-glass key logs in over OpenSSH.
        '';
      };
      group = mkOption {
        type = types.str;
        default = "nixlab-admins";
        description = "Pocket ID group whose members may log in as measles and deploy.";
      };
    };
  };

  config = {
    homelab.ssh.logins = lib.genAttrs people (_: admins);

    services.openssh.settings.AllowUsers = lib.concatLists (
      lib.mapAttrsToList (
        user: sources: map (address: "${user}@${address}") (addresses sources)
      ) cfg.logins
    );

    services.opkssh = lib.mkIf (cfg.pocketId.clientId != null) {
      enable = true;
      providers.pocket-id = {
        inherit issuer;
        inherit (cfg.pocketId) clientId;
        lifetime = "24h";
      };
      authorizations = map (user: {
        inherit user issuer;
        principal = "oidc:groups:${cfg.pocketId.group}";
      }) people;
    };

    users.users = lib.genAttrs people (_: {
      openssh.authorizedKeys.keys = lib.optional (
        breakGlassKey != null
      ) ''from="${lan.subnet}" ${breakGlassKey}'';
    });

    # opkssh fetches Pocket ID's keys (services/pocket-id.nix) on every login;
    # skip the router's hairpin NAT.
    networking.hosts.${nodes.seladonia.ip} = [ "id.${domain}" ];

    programs.ssh.knownHosts = lib.mapAttrs (name: node: {
      hostNames = [
        name
        "${name}.${lan.domain}"
        node.ip
      ];
      publicKey = node.sshHostKey;
    }) (lib.filterAttrs (_: node: node.sshHostKey != null) nodes);

    # WireGuard peers are admins and reach every port.
    networking.nftables.enable = true;
    networking.firewall.extraInputRules = ''
      ip saddr ${wireguard.subnet} accept
    ''
    + lib.concatLines (
      lib.mapAttrsToList (
        user: sources:
        ''ip saddr { ${lib.concatStringsSep ", " (addresses sources)} } tcp dport 22 accept comment "${user} from ${lib.concatStringsSep ", " sources}"''
      ) cfg.logins
    );
  };
}
