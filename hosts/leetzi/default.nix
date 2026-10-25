{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "leetzi";

  homelab.models.serveTo = {
    interface = "enp1s0f0np0";
    clients = [ "192.168.100.11" ];
  };
}
