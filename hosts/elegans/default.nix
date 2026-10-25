{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./networking.nix
  ];

  networking.hostName = "elegans";

  # From leetzi over ConnectX-7; keep homelab.models.local the same on
  # both Sparks.
  homelab.models.source = {
    host = "192.168.100.10";
    path = "/var/lib/models";
  };
}
