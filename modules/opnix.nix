{ config, inputs, ... }:
{
  imports = [ inputs.opnix.nixosModules.default ];

  # Keys must be camelCase; rendered to /var/lib/opnix/secrets/<key>.
  services.onepassword-secrets = {
    enable = config.services.onepassword-secrets.secrets != { };
    tokenFile = "/etc/opnix-token";

    systemdIntegration = {
      enable = true;
      restartOnChange = true;
    };
  };
}
