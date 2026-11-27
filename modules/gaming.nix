# Steam, GameMode, gamescope and MangoHud. Steam's own client (OpenGL/CEF)
# stays on the GPU that drives the display; its Vulkan games, DXVK (D3D9-11)
# and VKD3D-Proton (D3D12) prefer `homelab.gaming.gpu` and fall back to the
# others while it is away, e.g. passed through to a VM.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (config.homelab.gaming) gpu;

  env = {
    # Without a trailing `!` the other devices stay listed, after this one.
    MESA_VK_DEVICE_SELECT = gpu.pciId;
    # A miss falls back to the first device. DXVK_FILTER_DEVICE_NAME is left
    # out: a miss there leaves D3D games no adapter at all, and DXVK already
    # ranks discrete GPUs first.
    VKD3D_FILTER_DEVICE_NAME = gpu.name;
  }
  // lib.optionalAttrs (lib.hasPrefix "10de:" gpu.pciId) {
    # DLSS and Reflex; Proton hides NVAPI by default.
    PROTON_ENABLE_NVAPI = "1";
  };
in
{
  options.homelab.gaming.gpu = {
    pciId = mkOption {
      type = types.strMatching "[0-9a-f]{4}:[0-9a-f]{4}";
      description = "The GPU games render on, as `lspci -nn` shows its vendor:device.";
    };
    name = mkOption {
      type = types.str;
      description = "Its Vulkan device name, as `vulkaninfo --summary` shows it.";
    };
  };

  config = {
    programs.steam = {
      enable = true;
      package = pkgs.steam.override { extraEnv = env; };
      protontricks.enable = true;
    };

    programs.gamemode.enable = true;
    # Its polkit rule lets only this group switch governors and GPU clocks.
    users.users.measles.extraGroups = [ "gamemode" ];

    # Steam's bubblewrap sets no_new_privs, so a capSysNice wrapper would not
    # apply to gamescope started from a launch option.
    programs.gamescope.enable = true;
    environment.systemPackages = [ pkgs.mangohud ];

    homelab.vmTest.checks.gaming = ''
      with subtest("Steam's FHS env carries the game GPU selection"):
          for var, value in ${builtins.toJSON env}.items():
              got = machine.succeed(f"runuser -l measles -c 'steam-run printenv {var}'").strip()
              assert got == value, f"{var}: {got!r}, expected {value!r}"

      with subtest("measles may switch GameMode's governors and clocks"):
          machine.succeed("id -nG measles | grep -qw gamemode")
    '';
  };
}
