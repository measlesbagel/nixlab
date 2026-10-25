{ pkgs, ... }:
{
  enable = true;
  directory = "/home/measles";

  packages = with pkgs; [
    ripgrep
    fd
    jq
  ];
}
