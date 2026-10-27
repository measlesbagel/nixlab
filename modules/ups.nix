# NUT server on the `ups-server` host, LAN clients elsewhere.
# No early shutdowns: only an outlet cycle powers hosts back on.
{ config, lib, ... }:
let
  inherit (config.homelab) nodes;
  server = lib.head (
    lib.attrNames (lib.filterAttrs (_: node: lib.elem "ups-server" node.roles) nodes)
  );
  isServer = config.networking.hostName == server;

  # Can force every host down, so it is generated on the server and never
  # enters the shared vault.
  primaryPassword = "/var/lib/nut/primary-password";
  secondaryPassword = "/var/lib/opnix/secrets/nutSecondaryPassword";
in
lib.mkMerge [
  {
    # 1Password item: a random password in `password`.
    services.onepassword-secrets.secrets.nutSecondaryPassword = {
      reference = "op://homelab/nut-upsmon/password";
      services = if isServer then [ "upsd" ] else [ "upsmon" ];
    };
  }

  (lib.mkIf isServer {
    power.ups = {
      enable = true;
      mode = "netserver";
      openFirewall = true;
      ups.ups = {
        description = "APC Back-UPS Pro BN1500M2";
        driver = "usbhid-ups";
        port = "auto";
        directives = [
          # Low battery early enough for every host to finish shutting down.
          "ignorelb"
          "override.battery.charge.low = 30"
          "override.battery.runtime.low = 300"
          # Outlets go off two minutes after the server, which shuts down last.
          "offdelay = 120"
          "ondelay = 180"
        ];
      };
      upsd.listen = [ { address = "0.0.0.0"; } ];
      users = {
        primary = {
          upsmon = "primary";
          passwordFile = primaryPassword;
        };
        secondary = {
          upsmon = "secondary";
          passwordFile = secondaryPassword;
        };
      };
      upsmon.monitor.ups = {
        system = "ups@localhost";
        user = "primary";
        type = "primary";
        powerValue = 1;
      };
    };

    systemd.services.nut-primary-password = {
      description = "Generate the NUT primary password";
      before = [
        "upsd.service"
        "upsmon.service"
      ];
      requiredBy = [
        "upsd.service"
        "upsmon.service"
      ];
      unitConfig.ConditionPathExists = "!${primaryPassword}";
      serviceConfig.Type = "oneshot";
      script = ''
        umask 077
        mkdir -p /var/lib/nut
        head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > ${primaryPassword}
      '';
    };
  })

  (lib.mkIf (!isServer) {
    power.ups = {
      enable = true;
      mode = "netclient";
      # By IP: the router, and with it DNS, has no battery.
      upsmon.monitor.ups = {
        system = "ups@${nodes.${server}.ip}";
        user = "secondary";
        passwordFile = secondaryPassword;
        type = "secondary";
        powerValue = 1;
      };
    };
  })
]
