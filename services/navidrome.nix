{ config, ... }:
let
  nas = config.homelab.nodes.albipes;
in
{
  services.navidrome = {
    enable = true;
    settings = {
      Address = "127.0.0.1";
      MusicFolder = "/media/music";
      # Keep the regenerable cache off the snapshotted state dataset.
      CacheFolder = "/var/cache/navidrome";
    };
  };

  fileSystems."/media/music" = {
    device = "${nas.ip}:/tank/media/music";
    fsType = "nfs";
    options = [
      "ro"
      "x-systemd.automount"
      "noauto"
      "nofail"
      "nconnect=8"
      "rsize=1048576"
    ];
  };

  systemd.services.navidrome.unitConfig.RequiresMountsFor = [ "/media/music" ];

  services.caddy.virtualHosts."music.${config.homelab.domain}".extraConfig = ''
    reverse_proxy localhost:4533
  '';
}
