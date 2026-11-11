{ lib, pkgs, ... }:
{
  # One kernel on every host but the Sparks, which force NVIDIA's
  # (modules/spark.nix). Always a stable release, never an rc.
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
}
