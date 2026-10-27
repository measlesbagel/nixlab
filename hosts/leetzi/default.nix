{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "leetzi";

  # Over ConnectX-7, so the kernel compiles only on elegans.
  homelab.builder.remote = {
    host = "elegans";
    address = "192.168.100.11";
  };

  homelab.models.serveTo = {
    interface = "enp1s0f0np0";
    clients = [ "192.168.100.11" ];
  };
}
