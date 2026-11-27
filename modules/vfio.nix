# Dynamic GPU passthrough (VFIO) with Looking Glass for a dual-GPU desktop:
# the host stays on its iGPU while a libvirt hook hands the discrete NVIDIA GPU
# to selected VMs on start and returns it for PRIME offload on stop.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.homelab.vfio;

  pciAddressType = types.strMatching "[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\\.[0-7]";

  # Pinned master rev for the signed Windows IDD and `win:setGuestRes`, which
  # stable B7 lacks. Client and kvmfr are built from the same source.
  lookingGlassVersion = "B7-unstable-2026-11-26";
  lookingGlassSrc = pkgs.fetchFromGitHub {
    owner = "gnif";
    repo = "LookingGlass";
    rev = "1b485305d9267207701d01adbe7907e90bfd6990";
    hash = "sha256-ropEJC9+Gg85DS9XRuTb2IRGNNmUcA09Sy/cN6DTvZE=";
    fetchSubmodules = true;
  };

  lookingGlassClient = pkgs.looking-glass-client.overrideAttrs (old: {
    version = lookingGlassVersion;
    src = lookingGlassSrc;
    patches = [ ];
    buildInputs = old.buildInputs ++ [
      pkgs.elfutils
      pkgs.fuse3
      pkgs.libdecor
      pkgs.libunwind
    ];
  });

  lookingGlassKvmfr = config.boot.kernelPackages.kvmfr.overrideAttrs (_: {
    version = lookingGlassVersion;
    src = lookingGlassSrc;
    sourceRoot = "${lookingGlassSrc.name}/module";
  });

  gpuBusyCheck = ''
    busy_nodes=()
    for node in /dev/nvidia[0-9]* /dev/nvidiactl /dev/nvidia-uvm /dev/nvidia-modeset; do
      [ -e "$node" ] && busy_nodes+=("$node")
    done
    for dev in "''${gpu_devices[@]}"; do
      for node in "/dev/dri/by-path/pci-$dev-"*; do
        [ -e "$node" ] && busy_nodes+=("$node")
      done
    done
  '';

  vfioHook = pkgs.writeShellApplication {
    name = "vfio-gpu";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.kmod
      pkgs.psmisc
    ];
    text = ''
      domain="''${1:-}"
      operation="''${2:-}"
      subop="''${3:-}"

      vm_names=(${lib.escapeShellArgs cfg.vmNames})
      matched=0
      for vm in "''${vm_names[@]}"; do
        if [ "$domain" = "$vm" ]; then
          matched=1
          break
        fi
      done
      [ "$matched" -eq 1 ] || exit 0

      gpu_devices=(${lib.escapeShellArgs cfg.gpuDevices})

      unbind_pci() {
        local dev="$1"
        if [ -e "/sys/bus/pci/devices/$dev/driver/unbind" ]; then
          echo "$dev" > "/sys/bus/pci/devices/$dev/driver/unbind"
        fi
      }

      resize_bar() {
        local dev="$1"
        local resource="$2"
        local size="$3"
        local path="/sys/bus/pci/devices/$dev/resource''${resource}_resize"
        if [ -w "$path" ]; then
          echo "$size" > "$path" || echo "vfio-gpu: BAR$resource resize to $size on $dev skipped" >&2
        fi
      }

      if [ "$operation" = "prepare" ] && [ "$subop" = "begin" ]; then
        # Fail fast before unbinding if a desktop app still holds the GPU open.
        ${gpuBusyCheck}
        if [ "''${#busy_nodes[@]}" -gt 0 ] && fuser -s "''${busy_nodes[@]}" 2> /dev/null; then
          echo "vfio-gpu: refusing to unbind GPU while processes still hold it open:" >&2
          fuser -v "''${busy_nodes[@]}" >&2 || true
          exit 1
        fi

        for mod in nvidia_drm nvidia_modeset nvidia_uvm nvidia; do
          if grep -q "^''${mod} " /proc/modules; then
            modprobe -r "$mod"
          fi
        done

        for dev in "''${gpu_devices[@]}"; do
          unbind_pci "$dev"
        done

        ${lib.optionalString (cfg.resizeBar != null) ''
          # OVMF can fail to place a 32 GiB ReBAR window; shrink for the guest.
          resize_bar ${lib.escapeShellArg cfg.resizeBar.device} ${toString cfg.resizeBar.resource} ${toString cfg.resizeBar.guestSize}
        ''}

        modprobe vfio_pci
        for dev in "''${gpu_devices[@]}"; do
          echo "vfio-pci" > "/sys/bus/pci/devices/$dev/driver_override"
          echo "$dev" > /sys/bus/pci/drivers_probe
        done
      elif [ "$operation" = "release" ] && [ "$subop" = "end" ]; then
        for dev in "''${gpu_devices[@]}"; do
          if [ -e "/sys/bus/pci/drivers/vfio-pci/$dev" ]; then
            echo "$dev" > /sys/bus/pci/drivers/vfio-pci/unbind
          fi
          if [ -w "/sys/bus/pci/devices/$dev/driver_override" ]; then
            echo "" > "/sys/bus/pci/devices/$dev/driver_override"
          fi
        done

        ${lib.optionalString (cfg.resizeBar != null) ''
          resize_bar ${lib.escapeShellArg cfg.resizeBar.device} ${toString cfg.resizeBar.resource} ${toString cfg.resizeBar.hostSize}
        ''}

        modprobe nvidia
        modprobe nvidia_modeset
        modprobe nvidia_uvm
        modprobe nvidia_drm

        for dev in "''${gpu_devices[@]}"; do
          echo "$dev" > /sys/bus/pci/drivers_probe
        done
      fi
    '';
  };

  launcherVm = lib.head cfg.vmNames;

  win11Launch = pkgs.writeShellApplication {
    name = "win11-launch";
    runtimeInputs = [
      lookingGlassClient
      pkgs.coreutils
      pkgs.libnotify
      pkgs.libvirt
      pkgs.procps
      pkgs.psmisc
    ];
    text = ''
      vm=${lib.escapeShellArg launcherVm}
      gpu_devices=(${lib.escapeShellArgs cfg.gpuDevices})

      notify() {
        local urgency="$1"
        local body="$2"
        notify-send -u "$urgency" -a "Windows 11" "Windows 11" "$body" 2> /dev/null || true
      }

      state=$(virsh --connect qemu:///system domstate "$vm" 2> /dev/null || true)
      if [ -z "$state" ]; then
        msg="VM '$vm' is not defined in libvirt yet."
        echo "win11-launch: $msg" >&2
        notify critical "$msg"
        exit 1
      fi

      if [ "$state" != "running" ]; then
        ${gpuBusyCheck}
        if [ "''${#busy_nodes[@]}" -gt 0 ]; then
          pids=$(fuser "''${busy_nodes[@]}" 2> /dev/null | tr ' ' '\n' | grep -E '^[0-9]+$' | sort -u || true)
          if [ -n "$pids" ]; then
            # shellcheck disable=SC2086
            procs=$(ps -o comm= -p $pids 2> /dev/null | sort -u | paste -sd', ' -)
            msg="GPU is in use by: ''${procs:-unknown process}. Close it and try again."
            echo "win11-launch: $msg" >&2
            notify critical "$msg"
            exit 1
          fi
        fi

        notify normal "Starting $vm..."
        if ! err=$(virsh --connect qemu:///system start "$vm" 2>&1); then
          echo "win11-launch: $err" >&2
          notify critical "Failed to start $vm: $err"
          exit 1
        fi
      fi

      exec looking-glass-client
    '';
  };

  win11Shutdown = pkgs.writeShellApplication {
    name = "win11-shutdown";
    runtimeInputs = [
      pkgs.libnotify
      pkgs.libvirt
    ];
    text = ''
      vm=${lib.escapeShellArg launcherVm}
      state=$(virsh --connect qemu:///system domstate "$vm" 2> /dev/null || true)
      if [ "$state" = "running" ]; then
        virsh --connect qemu:///system shutdown "$vm"
        notify-send -u normal -a "Windows 11" "Windows 11" "Shutting down $vm..." 2> /dev/null || true
      else
        notify-send -u low -a "Windows 11" "Windows 11" "$vm is already stopped." 2> /dev/null || true
      fi
    '';
  };

  win11DesktopItem = pkgs.makeDesktopItem {
    name = "win11";
    desktopName = "Windows 11";
    comment = "Start Windows 11 VM in Looking Glass";
    exec = lib.getExe win11Launch;
    icon = "lg-logo";
    categories = [
      "System"
      "Emulator"
    ];
    actions.shutdown = {
      name = "Shut Down Windows 11";
      exec = lib.getExe win11Shutdown;
    };
  };

  vmRunning = pkgs.writeShellScript "libvirt-vm-running" ''
    PATH=${
      lib.makeBinPath [
        pkgs.gnugrep
        pkgs.libvirt
      ]
    }
    virsh list --name --state-running 2> /dev/null | grep -q .
  '';
in
{
  options.homelab.vfio = {
    enable = mkEnableOption "dynamic VFIO GPU passthrough and Looking Glass";

    vmNames = mkOption {
      type = types.nonEmptyListOf types.str;
      default = [ "win11" ];
      description = "Libvirt domain names that trigger dynamic GPU unbind/rebind; the first is used by the desktop launcher.";
    };

    igpuPciAddress = mkOption {
      type = pciAddressType;
      description = "PCI address of the host iGPU, pinned via stable /dev/dri/igpu-* symlinks.";
    };

    gpuDevices = mkOption {
      type = types.listOf pciAddressType;
      description = "PCI addresses of the discrete GPU and its companion functions (e.g. HDMI audio).";
    };

    resizeBar = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            device = mkOption { type = pciAddressType; };
            resource = mkOption {
              type = types.ints.unsigned;
              description = "PCI BAR index exposed as resource<N>_resize in sysfs.";
            };
            guestSize = mkOption {
              type = types.ints.unsigned;
              description = "Exponent N (2^N MiB) applied before binding the GPU to vfio-pci.";
            };
            hostSize = mkOption {
              type = types.ints.unsigned;
              description = "Exponent N (2^N MiB) restored after returning the GPU to the host.";
            };
          };
        }
      );
      default = null;
      description = "Optional Resizable BAR shrink/restore around VM handoff.";
    };

    kvmfrSizeMb = mkOption {
      type = types.ints.positive;
      default = 256;
      description = "Looking Glass kvmfr static shared-memory size in MiB (128 covers 4K SDR; 256 covers 4K HDR / dynamic IDD).";
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [ "measles" ];
      description = "Users granted libvirtd and kvm group membership for VM and Looking Glass access.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Do not bind vfio-pci in initrd: the GPU stays on nvidia for Linux PRIME
    # offload until the libvirt hook swaps it on VM start.
    boot.kernelParams = [ "iommu=pt" ];
    boot.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"
      "kvmfr"
    ];
    boot.extraModulePackages = [ lookingGlassKvmfr ];
    boot.extraModprobeConfig = ''
      options kvmfr static_size_mb=${toString cfg.kvmfrSizeMb}
      # Keep fbcon off the dGPU's outputs so nvidia_drm unloads cleanly.
      options nvidia_drm fbdev=0
    '';

    services.udev.extraRules = ''
      SUBSYSTEM=="kvmfr", GROUP="kvm", MODE="0660"
      KERNEL=="card[0-9]*", SUBSYSTEM=="drm", KERNELS=="${cfg.igpuPciAddress}", SYMLINK+="dri/igpu-card"
      KERNEL=="renderD[0-9]*", SUBSYSTEM=="drm", KERNELS=="${cfg.igpuPciAddress}", SYMLINK+="dri/igpu-render"
    '';

    # Pin Wayland compositors to the iGPU so they never hold /dev/dri on the dGPU.
    environment.sessionVariables = {
      AQ_DRM_DEVICES = "/dev/dri/igpu-card";
      WLR_DRM_DEVICES = "/dev/dri/igpu-card";
      KWIN_DRM_DEVICES = "/dev/dri/igpu-card";
    };

    # NoCoW on VM disk images avoids btrfs fragmentation and write amplification.
    systemd.tmpfiles.rules = [
      "d /var/lib/libvirt/images 0711 root root -"
      "h /var/lib/libvirt/images - - - - +C"
    ];

    virtualisation.libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        swtpm.enable = true;
        vhostUserPackages = [ pkgs.virtiofsd ];
        verbatimConfig = ''
          namespaces = []
          cgroup_device_acl = [
            "/dev/null", "/dev/full", "/dev/zero",
            "/dev/random", "/dev/urandom",
            "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
            "/dev/rtc", "/dev/hpet", "/dev/vfio/vfio",
            "/dev/kvmfr0"
          ]
        '';
      };
      hooks.qemu.vfio-gpu = lib.getExe vfioHook;
    };

    virtualisation.spiceUSBRedirection.enable = true;
    programs.virt-manager.enable = true;

    environment.systemPackages = [
      lookingGlassClient
      win11Launch
      win11Shutdown
      win11DesktopItem
    ];
    environment.etc."looking-glass-client.ini".text = ''
      [app]
      shmFile=/dev/kvmfr0

      [win]
      setGuestRes=yes
      keepAspect=no
      forceAspect=no
    '';

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [
        "libvirtd"
        "kvm"
      ];
    });

    homelab.reboot.busyWhen."a libvirt VM is running" = "${vmRunning}";

    homelab.vmTest.checks.vfio = ''
      with subtest("libvirtd, kvmfr, vfio_pci, NoCoW images dir and desktop launcher are ready"):
          machine.wait_for_unit("libvirtd.service")
          machine.succeed(
              "virsh list --all",
              "lsmod | grep -q '^kvmfr '",
              "lsmod | grep -q '^vfio_pci '",
              '[ "$(stat -c %G:%a /dev/kvmfr0)" = kvm:660 ]',
              "${pkgs.e2fsprogs}/bin/lsattr -d /var/lib/libvirt/images | awk '{print $1}' | grep -q C",
              "test -x /var/lib/libvirt/hooks/qemu.d/vfio-gpu",
              # Non-VFIO VM names must be a no-op.
              "/var/lib/libvirt/hooks/qemu.d/vfio-gpu unrelated-vm prepare begin -",
              "(runuser -u ${lib.escapeShellArg (lib.head cfg.users)} -- looking-glass-client --help 2>&1 || true) | grep -q 'win:setGuestRes'",
              "command -v win11-launch",
              "command -v win11-shutdown",
              "test -f /run/current-system/sw/share/applications/win11.desktop",
              "command -v nvidia-offload",
          )
          for user in ${builtins.toJSON cfg.users}:
              machine.succeed(f"id -nG {quote(user)} | tr ' ' '\\n' | grep -qx libvirtd")
              machine.succeed(f"id -nG {quote(user)} | tr ' ' '\\n' | grep -qx kvm")
    '';
  };
}
