{ pkgs, ... }:
{
  enable = true;
  directory = "/home/measles";

  packages = with pkgs; [
    # Shell
    starship
    eza
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
    kitty
    ghostty
    alacritty
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
    # Umbriel's autostart runs Python scripts through `env python3`.
    python3
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

  # cachyos-config.fish, which ~/.config/fish/config.fish sourced on CachyOS.
  xdg.config.files."fish/conf.d/nixlab.fish".text = ''
    fish_add_path ~/.local/bin ~/.cargo/bin

    function fish_greeting
        fastfetch
    end

    set -x MANROFFOPT -c
    set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
    set -g __done_min_cmd_duration 10000
    set -g __done_notification_urgency_level low

    function history
        builtin history --show-time='%F %T ' $argv
    end

    alias ls='eza -al --color=always --group-directories-first --icons=always'
    alias la='eza -a --color=always --group-directories-first --icons=always'
    alias ll='eza -l --color=always --group-directories-first --icons=always'
    alias lt='eza -aT --color=always --group-directories-first --icons=always'
  '';

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
