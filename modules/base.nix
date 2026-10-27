{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;

  # nixos-generate-config's not-detected.nix sets this, but these host
  # configs are hand-written; without it no linux-firmware is installed.
  hardware.enableRedistributableFirmware = true;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [ "deploy" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  networking.useDHCP = lib.mkDefault true;

  # Who may log in, and from where, is modules/ssh.nix; LAN port 22 stays shut
  # to everything else.
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Logins are opkssh or the break-glass key (modules/ssh.nix).
  users.users = {
    measles = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    deploy = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
  };
  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [
    git
    htop
    vim
  ];

  system.stateVersion = "25.11";
}
