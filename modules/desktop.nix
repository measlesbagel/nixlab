# The workstation's Wayland desktop: Umbriel and the Noctalia shell, behind
# greetd's Noctalia greeter. Their configs stay in the user's home, where
# Noctalia and the user's tools rewrite them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = "measles";
  inherit (config.fonts.fontconfig) defaultFonts;
in
{
  programs.umbriel.enable = true;
  # No unit of its own: Umbriel's autostart runs it, and a second instance
  # would contend for org.freedesktop.Notifications.
  programs.noctalia.enable = true;

  services.displayManager.noctalia-greeter.enable = true;

  # greetd's PAM stack is login's, which this unlocks the keyring in.
  services.gnome.gnome-keyring.enable = true;

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # What Noctalia's panels and Nautilus talk to.
  services.upower.enable = true;
  services.power-profiles-daemon.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  services.flatpak.enable = true;

  # `op` unlocks through the GUI, which needs a polkit owner; provisioning
  # (docs/provisioning.md) runs `op` here.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ user ];
  };

  # Prebuilt tools in ~/.local/bin expect /lib64/ld-linux-x86-64.so.2.
  programs.nix-ld.enable = true;

  virtualisation.podman.enable = true;

  environment.systemPackages = with pkgs; [
    adw-gtk3
    adwaita-icon-theme
    kdePackages.qt6ct
    wl-clipboard
  ];

  fonts = {
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      cantarell-fonts
      dejavu_fonts
      liberation_ttf
      open-sans
      font-awesome
      nerd-fonts.jetbrains-mono
      nerd-fonts._0xproto
      nerd-fonts.agave
      nerd-fonts.meslo-lg
      nerd-fonts.monaspace
      nerd-fonts.symbols-only
    ];
    fontconfig.defaultFonts = {
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
      monospace = [ "Noto Sans Mono" ];
      emoji = [ "Noto Color Emoji" ];
    };
  };

  homelab.vmTest.checks.desktop =
    let
      fcMatch = lib.getExe' pkgs.fontconfig "fc-match";
      pactl = lib.getExe' pkgs.pulseaudio "pactl";
    in
    # Umbriel and Noctalia are not started: SceneFX needs a DRM render node,
    # which the VM lacks.
    ''
      with subtest("greetd shows the Noctalia greeter"):
          machine.wait_for_unit("greetd.service")
          machine.wait_until_succeeds("journalctl -b -t noctalia-greeter -o cat | grep -q 'presented first frame'", timeout=timedelta(minutes=1))

      with subtest("fontconfig resolves the desktop's font families to installed fonts"):
          for pattern, family in {
              "sans-serif": ${builtins.toJSON (lib.head defaultFonts.sansSerif)},
              "serif": ${builtins.toJSON (lib.head defaultFonts.serif)},
              "monospace": ${builtins.toJSON (lib.head defaultFonts.monospace)},
              "emoji": ${builtins.toJSON (lib.head defaultFonts.emoji)},
              "JetBrainsMono Nerd Font Mono": "JetBrainsMono Nerd Font Mono",
          }.items():
              matched = machine.succeed(f"${fcMatch} -f '%{{family}}' {quote(pattern)}")
              assert family in matched.split(","), f"{pattern} matched {matched}, not {family}"

      with subtest("${user}'s session runs PipeWire, its PulseAudio server and WirePlumber"):
          uid = machine.succeed("id -u ${user}").strip()
          machine.succeed(f"systemctl start user@{uid}.service")

          def as_user(command: str) -> str:
              return f"runuser -u ${user} -- env XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus {command}"

          machine.wait_until_succeeds(as_user("${pactl} info") + " | grep -q 'Server Name: PulseAudio (on PipeWire'", timeout=timedelta(minutes=1))
          machine.wait_until_succeeds(as_user("systemctl --user is-active pipewire.service wireplumber.service"), timeout=timedelta(minutes=1))

      with subtest("Umbriel's portal preference is on xdg-desktop-portal's data path"):
          machine.succeed("grep -qx 'default=umbriel;gtk' /run/current-system/sw/share/xdg-desktop-portal/umbriel-portals.conf")
    '';
}
