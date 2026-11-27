# Windows 11 VM with dynamic VFIO on chilense

`chilense` keeps its Linux desktop on the Ryzen 7 7800X3D iGPU (`0000:0c:00.0`)
so the RTX 4090 (`0000:01:00.0`) can serve Linux games via `nvidia-offload` and
dynamically unbind to `vfio-pci` when the `win11` VM starts (`modules/vfio.nix`).
Looking Glass (master build with signed IDD + `win:setGuestRes=yes`) streams the
VM into a resizable Wayland window over `/dev/kvmfr0`.

## Physical wiring (ROG Strix B650E-I + PG32UCDM)

- **Monitor -> motherboard DP-Alt USB-C (10 Gbps, DP icon):** Use a USB-C to
  DisplayPort 1.4 cable, or a USB-C to USB-C cable with the PG32UCDM set to
  **USB 2.0 / 4-lane DP** mode so DP 1.4 + DSC reaches 4K @ 240 Hz. Do not use
  the motherboard HDMI port (`amdgpu` caps HDMI at 2.0 / 4K @ 60 Hz on Linux).
- **DisplayPort dummy plug -> RTX 4090 (optional once IDD is installed):** Only
  needed if you want a physical output before the signed Looking Glass IDD is
  installed inside Windows.
- **RTL8159 10GbE adapter -> motherboard 20 Gbps USB-C:** Unchanged.

## Declarative VM & Windows-as-code

Everything except the Microsoft Windows 11 ISO itself lives in `nixlab`:

- **Libvirt domain (`modules/vfio.nix`):** `libvirtd-define-win11.service`
  defines `win11` declaratively on boot (Q35, OVMF Secure Boot, TPM 2.0, 12
  vCPUs, 32 GiB dynamic RAM, sparse 500 GiB VirtIO-SCSI `qcow2` with
  `discard='unmap'`, `/dev/kvmfr0` 256 MiB IVSHMEM, QEMU Guest Agent, RTX 4090
  group 12, MediaTek Wi-Fi 6E group 19, and empty CPU USB 3.1 group 26).
- **Storage (`hosts/chilense/disko.nix`):** `/var/lib/libvirt/images` is its own
  `@vms` btrfs subvolume (`+C` NoCoW via tmpfiles, excluded from btrbk
  snapshots/replication). Work files go in `/home/measles/win-share` (`virtiofs`
  tag `win-share`) so they stay on `@home` and participate in backups.
- **Unattended install (`windows/autounattend.xml`):** Bundled with Windows 11
  x64 VirtIO drivers (`pkgs.virtio-win`), `bootstrap.ps1`, and `win11.dsc.yaml`
  into a Nix-built `win11-bootstrap.iso`. Places WinRE *before* `C:` so `C:` is
  always the final partition and can be extended cleanly.
- **Ongoing packages & settings (`windows/win11.dsc.yaml`):** Mounted live
  read-only into Windows via `virtiofs` (`win-config` -> `Y:\`) and applied
  idempotently from Linux via `win11-apply` (over the local QEMU Guest Agent
  socket, with no passwords or SSH keys in the repo).

## First-time installation

1. Download the official **Windows 11 Multi-Edition x64 ISO** from Microsoft
   into `/var/lib/libvirt/images/iso/Win11.iso`.
2. Run:

   ```console
   win11-install /var/lib/libvirt/images/iso/Win11.iso
   ```

   This creates the sparse 500 GiB `qcow2` disk, attaches both `Win11.iso` and
   the Nix-built `win11-bootstrap.iso`, starts `win11`, and opens `virt-viewer`.
   Windows installs unattended, loads VirtIO drivers, installs guest tools +
   QEMU Guest Agent, and runs `windows/bootstrap.ps1` + `windows/win11.dsc.yaml`.
3. Inside Windows, install the NVIDIA GeForce driver (via NVIDIA App) and the
   matching bleeding-edge signed **Looking Glass IDD** host package from
   `looking-glass.io` (matching the pinned master rev in `modules/vfio.nix`).
4. Shut down Windows and finalize the domain XML (drops QXL and both ISOs):

   ```console
   win11-install --finalize
   ```

## Daily usage

- **Start / view:** Launch **Windows 11** from your app launcher (`win11-launch`).
  It checks whether anything still holds the RTX 4090 open (notifying you with
  the process name if busy), starts `win11` if stopped, and opens Looking Glass.
- **Dynamic resize on Niri/Umbriel:** `/etc/looking-glass-client.ini` sets
  `win:setGuestRes=yes`, `keepAspect=no`, and `forceAspect=no`, so cycling
  column widths (`1/3`, `1/2`, `2/3`, `3/4`) resizes the Looking Glass IDD
  virtual display to fill the column with no letterboxing. Press
  `ScrollLock + =` anytime to force a manual sync.
- **Apply updated Windows config:** Edit `windows/win11.dsc.yaml`, rebuild
  NixOS, and while `win11` is running execute:

  ```console
  win11-apply
  ```
- **Shut down:** Use Windows' Start menu, or right-click **Windows 11** in your
  launcher and pick **Shut Down Windows 11** (`win11-shutdown`). The hook
  returns the RTX 4090, CPU threads, and RAM to Linux automatically.
