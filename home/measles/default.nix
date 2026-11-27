{
  config,
  lib,
  pkgs,
  ...
}:
{
  enable = true;
  directory = "/home/measles";

  packages = with pkgs; [
    # Shell
    bat
    fastfetch
    btop
    glances
    yazi
    micro
    ripgrep
    fd
    jq
    duf
    pv
    _7zz
    unzip
    wget
    rsync
    # Desktop
    zed-editor
    meld
    obsidian
    firefox
    google-chrome
    discord
    vlc
    nautilus
    pavucontrol
    btrfs-assistant
    nwg-look
    zenity
    libnotify
    cliphist
    wtype
    podman-desktop
    # Development
    gh
    tea
    just
    just-lsp
    mise
    go
    gopls
    rustup
    zig
    zls
    nodejs
    bun
    deno
    pnpm
    typescript
    biome
    uv
    ruff
    ty
    pipx
    kubectl
    kubernetes-helm
    opentofu
    talosctl
    scrcpy
  ];

  # Ghostty also reads ~/.config/ghostty/config.ghostty, which stays
  # hand-written and wins where both set a key.
  rum.programs.ghostty = {
    enable = true;
    settings.command = lib.getExe config.rum.programs.nushell.package;
  };

  rum.programs.nushell = {
    enable = true;
    settings.show_banner = false;
    extraConfig = ''
      $env.PATH = ($env.PATH | prepend [
        ($env.HOME | path join .local/bin)
        ($env.HOME | path join .cargo/bin)
        ($env.HOME | path join go/bin)
      ] | uniq)

      fastfetch
    '';
  };

  # The CachyOS entry starts /opt/1Password/1password.
  xdg.config.files."autostart/com.onepassword.OnePassword.desktop" = {
    clobber = true;
    text = ''
      [Desktop Entry]
      Type=Application
      Name=1Password
      Exec=1password --silent
      Icon=1password
      X-GNOME-Autostart-enabled=true
    '';
  };
}
