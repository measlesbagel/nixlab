# Dynamic GPU passthrough (VFIO) with Looking Glass and declarative Windows 11
# VM provisioning for a dual-GPU desktop: the host stays on its iGPU while a
# libvirt hook hands the discrete NVIDIA GPU to selected VMs on start and
# returns it for PRIME offload on stop.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkOption types;
  cfg = config.homelab.vfio;
  vmCfg = cfg.vm;

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

  # Live read-only copy of windows/ mounted inside the guest via virtiofs.
  winConfigDir = pkgs.runCommand "win11-config" { } ''
    mkdir -p "$out"
    cp ${vmCfg.configDir}/win11.dsc.yaml "$out/win11.dsc.yaml"
    cp ${vmCfg.configDir}/bootstrap.ps1 "$out/bootstrap.ps1"
  '';

  # Unattended install CD combining autounattend.xml, bootstrap.ps1,
  # win11.dsc.yaml, and the Windows 11 x64 VirtIO drivers/guest tools.
  winBootstrapIso = pkgs.runCommand "win11-bootstrap.iso" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
    mkdir -p stage/drivers
    cp ${vmCfg.configDir}/autounattend.xml stage/autounattend.xml
    cp ${vmCfg.configDir}/bootstrap.ps1 stage/bootstrap.ps1
    cp ${vmCfg.configDir}/win11.dsc.yaml stage/win11.dsc.yaml
    cp ${pkgs.virtio-win}/virtio-win-guest-tools.exe stage/virtio-win-guest-tools.exe
    cp ${pkgs.virtio-win}/guest-agent/qemu-ga-x86_64.msi stage/qemu-ga-x86_64.msi
    for drv in vioscsi NetKVM viofs vioserial Balloon; do
      mkdir -p "stage/drivers/$drv"
      cp -r "${pkgs.virtio-win}/$drv/w11/amd64/." "stage/drivers/$drv/"
    done
    xorriso -as mkisofs -R -J -joliet-long -V WIN11BOOT -o "$out" stage
  '';

  parsePci =
    addr:
    let
      parts = lib.splitString ":" addr;
      slotFn = lib.splitString "." (lib.elemAt parts 2);
    in
    {
      domain = "0x${lib.elemAt parts 0}";
      bus = "0x${lib.elemAt parts 1}";
      slot = "0x${lib.elemAt slotFn 0}";
      function = "0x${lib.elemAt slotFn 1}";
    };

  renderHostdev =
    managed: addr:
    let
      p = parsePci addr;
    in
    ''
      <hostdev mode='subsystem' type='pci' managed='${if managed then "yes" else "no"}'>
        <source>
          <address domain='${p.domain}' bus='${p.bus}' slot='${p.slot}' function='${p.function}'/>
        </source>
      </hostdev>
    '';

  kvmfrSizeBytes = cfg.kvmfrSizeMb * 1024 * 1024;
  vcpuCores = vmCfg.vcpus / 2;

  # Generates either the daily VFIO+Looking Glass domain XML (installIso = null)
  # or the first-boot unattended-install XML (adds QXL video + Windows/bootstrap ISOs).
  mkDomainXml =
    {
      installIso ? null,
    }:
    let
      installing = installIso != null;
    in
    ''
      <domain type='kvm' xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'>
        <name>${vmCfg.name}</name>
        <uuid>${vmCfg.uuid}</uuid>
        <memory unit='GiB'>${toString vmCfg.memoryGiB}</memory>
        <currentMemory unit='GiB'>${toString vmCfg.memoryGiB}</currentMemory>
        <memoryBacking>
          <source type='memfd'/>
          <access mode='shared'/>
        </memoryBacking>
        <vcpu placement='static'>${toString vmCfg.vcpus}</vcpu>
        <os firmware='efi'>
          <type arch='x86_64' machine='q35'>hvm</type>
          <firmware>
            <feature enabled='yes' name='secure-boot'/>
          </firmware>
          <bootmenu enable='yes'/>
        </os>
        <features>
          <acpi/>
          <apic/>
          <hyperv mode='custom'>
            <relaxed state='on'/>
            <vapic state='on'/>
            <spinlocks state='on' retries='8191'/>
            <vpindex state='on'/>
            <synic state='on'/>
            <stimer state='on'/>
            <vendor_id state='on' value='nixlabvfio01'/>
          </hyperv>
          <kvm>
            <hidden state='on'/>
          </kvm>
          <vmport state='off'/>
          <smm state='on'/>
        </features>
        <cpu mode='host-passthrough' check='none' migratable='off'>
          <topology sockets='1' dies='1' cores='${toString vcpuCores}' threads='2'/>
          <feature policy='disable' name='hypervisor'/>
        </cpu>
        <clock offset='localtime'>
          <timer name='rtc' tickpolicy='catchup'/>
          <timer name='pit' tickpolicy='delay'/>
          <timer name='hpet' present='no'/>
          <timer name='hypervclock' present='yes'/>
        </clock>
        <on_poweroff>destroy</on_poweroff>
        <on_reboot>restart</on_reboot>
        <on_crash>destroy</on_crash>
        <devices>
          <emulator>${pkgs.qemu_kvm}/bin/qemu-system-x86_64</emulator>
          <controller type='scsi' model='virtio-scsi'/>
          <disk type='file' device='disk'>
            <driver name='qemu' type='qcow2' cache='none' io='native' discard='unmap'/>
            <source file='${vmCfg.diskPath}'/>
            <target dev='sda' bus='scsi'/>
            <boot order='${if installing then "2" else "1"}'/>
          </disk>
          ${lib.optionalString installing ''
            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='${installIso}'/>
              <target dev='sdb' bus='sata'/>
              <readonly/>
              <boot order='1'/>
            </disk>
            <disk type='file' device='cdrom'>
              <driver name='qemu' type='raw'/>
              <source file='${winBootstrapIso}'/>
              <target dev='sdc' bus='sata'/>
              <readonly/>
            </disk>
          ''}
          <filesystem type='mount' accessmode='passthrough'>
            <driver type='virtiofs'/>
            <source dir='${vmCfg.shareDir}'/>
            <target dir='win-share'/>
          </filesystem>
          <filesystem type='mount' accessmode='passthrough'>
            <driver type='virtiofs'/>
            <source dir='${winConfigDir}'/>
            <target dir='win-config'/>
            <readonly/>
          </filesystem>
          <interface type='user'>
            <model type='virtio'/>
          </interface>
          <channel type='unix'>
            <target type='virtio' name='org.qemu.guest_agent.0'/>
          </channel>
          <channel type='spicevmc'>
            <target type='virtio' name='com.redhat.spice.0'/>
          </channel>
          <input type='mouse' bus='virtio'/>
          <input type='keyboard' bus='virtio'/>
          <graphics type='spice' autoport='yes'>
            <listen type='address' address='127.0.0.1'/>
            <image compression='off'/>
          </graphics>
          <sound model='ich9'/>
          <audio id='1' type='spice'/>
          <video>
            <model type='${if installing then "qxl" else "none"}'/>
          </video>
          <tpm model='tpm-crb'>
            <backend type='emulator' version='2.0'/>
          </tpm>
          <memballoon model='virtio'/>
          ${lib.concatMapStrings (renderHostdev false) cfg.gpuDevices}
          ${lib.concatMapStrings (renderHostdev true) vmCfg.extraPciDevices}
        </devices>
        <qemu:commandline>
          <qemu:arg value='-device'/>
          <qemu:arg value='{"driver":"ivshmem-plain","id":"shmem0","memdev":"looking-glass"}'/>
          <qemu:arg value='-object'/>
          <qemu:arg value='{"qom-type":"memory-backend-file","id":"looking-glass","mem-path":"/dev/kvmfr0","size":${toString kvmfrSizeBytes},"share":true}'/>
        </qemu:commandline>
      </domain>
    '';

  domainXmlFile = pkgs.writeText "${vmCfg.name}.xml" (mkDomainXml { });
  installXmlTemplate = pkgs.writeText "${vmCfg.name}-install.xml" (mkDomainXml {
    installIso = "@INSTALL_ISO@";
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

  launcherVm = vmCfg.name;

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

  win11Install = pkgs.writeShellApplication {
    name = "win11-install";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.libvirt
      pkgs.qemu_kvm
      pkgs.virt-viewer
    ];
    text = ''
      vm=${lib.escapeShellArg vmCfg.name}
      disk=${lib.escapeShellArg vmCfg.diskPath}
      size="${toString vmCfg.diskSizeGiB}G"

      if [ "''${1:-}" = "--finalize" ]; then
        virsh --connect qemu:///system define ${domainXmlFile}
        echo "Restored $vm to normal VFIO + Looking Glass XML (install ISOs and QXL removed)."
        exit 0
      fi

      iso="''${1:-}"
      if [ -z "$iso" ] || [ ! -f "$iso" ]; then
        echo "usage: win11-install /path/to/Win11.iso" >&2
        echo "       win11-install --finalize   # remove install ISOs & QXL after setup" >&2
        exit 1
      fi
      iso=$(readlink -f "$iso")

      if [ ! -e "$disk" ]; then
        echo "Creating sparse $size qcow2 disk at $disk..."
        qemu-img create -f qcow2 "$disk" "$size"
      fi

      tmp=$(mktemp)
      trap 'rm -f "$tmp"' EXIT
      sed "s|@INSTALL_ISO@|$iso|g" ${installXmlTemplate} > "$tmp"
      virsh --connect qemu:///system define "$tmp"
      virsh --connect qemu:///system start "$vm"
      echo "Opening SPICE viewer for unattended Windows 11 setup..."
      echo "Once Windows finishes bootstrapping and Looking Glass IDD is installed, shut down and run: win11-install --finalize"
      exec virt-viewer --connect qemu:///system --wait "$vm"
    '';
  };

  win11Apply = pkgs.writeShellApplication {
    name = "win11-apply";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.libvirt
    ];
    text = ''
      vm=${lib.escapeShellArg vmCfg.name}
      state=$(virsh --connect qemu:///system domstate "$vm" 2> /dev/null || true)
      if [ "$state" != "running" ]; then
        echo "win11-apply: $vm is not running (start it with win11-launch first)." >&2
        exit 1
      fi

      payload=$(jq -cn '{
        execute: "guest-exec",
        arguments: {
          path: "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
          arg: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "Y:\\bootstrap.ps1"],
          "capture-output": true
        }
      }')

      pid=$(virsh --connect qemu:///system qemu-agent-command "$vm" "$payload" | jq -r '.return.pid')
      printf 'win11-apply: running Y:\\bootstrap.ps1 in %s (guest pid %s)...\n' "$vm" "$pid"

      while true; do
        status=$(virsh --connect qemu:///system qemu-agent-command "$vm" \
          "$(jq -cn --argjson pid "$pid" '{execute: "guest-exec-status", arguments: {pid: $pid}}')")
        exited=$(jq -r '.return.exited' <<< "$status")
        if [ "$exited" = "true" ]; then
          out=$(jq -r '.return["out-data"] // empty' <<< "$status")
          err=$(jq -r '.return["err-data"] // empty' <<< "$status")
          code=$(jq -r '.return.exitcode // 1' <<< "$status")
          [ -n "$out" ] && printf '%s' "$out" | base64 -d
          [ -n "$err" ] && printf '%s' "$err" | base64 -d >&2
          exit "$code"
        fi
        sleep 2
      done
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
      description = "Libvirt domain names that trigger dynamic GPU unbind/rebind.";
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
      type = types.nonEmptyListOf types.str;
      default = [ "measles" ];
      description = "Users granted libvirtd and kvm group membership for VM and Looking Glass access.";
    };

    vm = {
      name = mkOption {
        type = types.str;
        default = lib.head cfg.vmNames;
        description = "Domain name for the declaratively defined Windows 11 VM.";
      };
      uuid = mkOption {
        type = types.str;
        default = "4b7f2b4e-8c7a-4b6d-9d21-6c5f3f1d0a11";
        description = "Stable libvirt domain UUID so rebuilds update the same VM in place.";
      };
      vcpus = mkOption {
        type = types.ints.positive;
        default = 12;
        description = "Even count of vCPUs (exposed as cores = vcpus / 2, threads = 2).";
      };
      memoryGiB = mkOption {
        type = types.ints.positive;
        default = 32;
        description = "Guest RAM in GiB (allocated dynamically while running, freed on shutdown).";
      };
      diskPath = mkOption {
        type = types.str;
        default = "/var/lib/libvirt/images/${vmCfg.name}.qcow2";
        description = "Path to the sparse qcow2 system disk on the NoCoW @vms subvolume.";
      };
      diskSizeGiB = mkOption {
        type = types.ints.positive;
        default = 500;
        description = "Maximum virtual size in GiB of the thin-provisioned qcow2 system disk.";
      };
      extraPciDevices = mkOption {
        type = types.listOf pciAddressType;
        default = [ ];
        description = "Additional isolated PCI devices passed through with libvirt managed='yes' (e.g. Wi-Fi 6E or empty USB 3.1 controller).";
      };
      shareDir = mkOption {
        type = types.str;
        default = "/home/${lib.head cfg.users}/win-share";
        description = "Host directory exposed to Windows via virtiofs (`win-share`).";
      };
      configDir = mkOption {
        type = types.path;
        default = ../windows;
        description = "Directory holding autounattend.xml, bootstrap.ps1 and win11.dsc.yaml.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.mod vmCfg.vcpus 2 == 0;
        message = "homelab.vfio.vm.vcpus must be even (2 threads per core).";
      }
      {
        assertion = lib.elem vmCfg.name cfg.vmNames;
        message = "homelab.vfio.vm.name (${vmCfg.name}) must be listed in homelab.vfio.vmNames.";
      }
    ];

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
      "d /var/lib/libvirt/images/iso 0755 root root -"
      "d ${vmCfg.shareDir} 0755 ${lib.head cfg.users} users -"
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

    # Declaratively define the VM in libvirt whenever it is stopped; if it is
    # currently running, leave it untouched until the next boot/rebuild.
    systemd.services."libvirtd-define-${vmCfg.name}" = {
      description = "Define declarative libvirt domain ${vmCfg.name}";
      wantedBy = [ "multi-user.target" ];
      after = [ "libvirtd.service" ];
      requires = [ "libvirtd.service" ];
      path = [ pkgs.libvirt ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        state=$(virsh --connect qemu:///system domstate ${lib.escapeShellArg vmCfg.name} 2> /dev/null || true)
        if [ "$state" != "running" ]; then
          virsh --connect qemu:///system define ${domainXmlFile}
        fi
      '';
    };

    virtualisation.spiceUSBRedirection.enable = true;
    programs.virt-manager.enable = true;

    environment.systemPackages = [
      lookingGlassClient
      win11Launch
      win11Shutdown
      win11Install
      win11Apply
      win11DesktopItem
    ];
    environment.etc = {
      "looking-glass-client.ini".text = ''
        [app]
        shmFile=/dev/kvmfr0

        [win]
        setGuestRes=yes
        keepAspect=no
        forceAspect=no
      '';
      "libvirt/${vmCfg.name}.xml".source = domainXmlFile;
    };

    users.users = lib.genAttrs cfg.users (_: {
      extraGroups = [
        "libvirtd"
        "kvm"
      ];
    });

    homelab.reboot.busyWhen."a libvirt VM is running" = "${vmRunning}";

    homelab.vmTest.checks.vfio = ''
      with subtest("libvirtd, kvmfr, vfio_pci, declarative win11 domain and desktop launcher are ready"):
          machine.wait_for_unit("libvirtd-define-${vmCfg.name}.service")
          machine.succeed(
              "virt-xml-validate /etc/libvirt/${vmCfg.name}.xml",
              "virsh dominfo ${lib.escapeShellArg vmCfg.name} | grep -q 'CPU(s):.*${toString vmCfg.vcpus}'",
              "test -s ${winBootstrapIso}",
              "lsmod | grep -q '^kvmfr '",
              "lsmod | grep -q '^vfio_pci '",
              '[ "$(stat -c %G:%a /dev/kvmfr0)" = kvm:660 ]',
              "${pkgs.e2fsprogs}/bin/lsattr -d /var/lib/libvirt/images | awk '{print $1}' | grep -q C",
              "test -d ${lib.escapeShellArg vmCfg.shareDir}",
              "test -x /var/lib/libvirt/hooks/qemu.d/vfio-gpu",
              # Non-VFIO VM names must be a no-op.
              "/var/lib/libvirt/hooks/qemu.d/vfio-gpu unrelated-vm prepare begin -",
              "(runuser -u ${lib.escapeShellArg (lib.head cfg.users)} -- looking-glass-client --help 2>&1 || true) | grep -q 'win:setGuestRes'",
              "command -v win11-launch",
              "command -v win11-shutdown",
              "command -v win11-install",
              "command -v win11-apply",
              "test -f /run/current-system/sw/share/applications/win11.desktop",
              "command -v nvidia-offload",
          )
          for user in ${builtins.toJSON cfg.users}:
              machine.succeed(f"id -nG {quote(user)} | tr ' ' '\\n' | grep -qx libvirtd")
              machine.succeed(f"id -nG {quote(user)} | tr ' ' '\\n' | grep -qx kvm")
    '';
  };
}
