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
- **DisplayPort dummy plug -> RTX 4090 (optional once IDD is installed):** Handy
  during initial Windows/NVIDIA driver setup; once the signed Looking Glass IDD
  is installed inside Windows, no physical dummy plug is required.
- **RTL8159 10GbE adapter -> motherboard 20 Gbps USB-C:** Unchanged.

## Storage layout

`/var/lib/libvirt/images` is backed by its own `@vms` btrfs subvolume
(`hosts/chilense/disko.nix`) with the `+C` (NoCoW) attribute set by tmpfiles and
excluded from btrbk snapshots/replication.

- Create a thin-provisioned `qcow2` disk (e.g. 500 GiB max) with VirtIO-SCSI and
  `discard='unmap'` so it only consumes written blocks on the 4 TB NVMe and
  avoids needing to fight Windows' trailing Recovery Partition later.
- Keep work files (scans, CAD, configs) on a `virtiofs` share under `/home/measles`
  so they remain native on `@home` and participate in normal snapshots/backups.

## Creating the `win11` VM

Create a Windows 11 guest named `win11` in `virt-manager` (matched by
`homelab.vfio.vmNames`):

1. **Chipset & firmware:** Q35 with UEFI Secure Boot (OVMF) and emulated
   TPM 2.0 (`swtpm`).
2. **CPU & memory:** Assign 8–12 host threads (`host-passthrough`) and 16–32 GiB
   RAM (returned to Linux on shutdown). Enable shared memory backing under
   *Memory* (required for `virtiofs`).
3. **PCI host devices (pass both GPU functions together):**
   - `0000:01:00.0` (RTX 4090 VGA) and `0000:01:00.1` (RTX 4090 Audio) —
     IOMMU group 12.
   - Optional peripheral passthrough (each is in its own IOMMU group, so libvirt
     manages detach/reattach automatically):
     - `0000:09:00.0` — onboard MediaTek MT7922 Wi-Fi 6E (IOMMU group 19; leaves
       host Bluetooth on `0a:00.0` untouched) for wireless 3D scanning.
     - `0000:0c:00.4` — empty CPU USB 3.1 10 Gbps controller (IOMMU group 26)
       for wired USB scanners or a Wi-Fi 6 USB dongle.
4. **Looking Glass IVSHMEM device (`/dev/kvmfr0`):** Add the `qemu` XML
   namespace (`xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"`) to
   `<domain>` via `virsh edit win11`, and add this `<qemu:commandline>` block
   (matching `homelab.vfio.kvmfrSizeMb`, default 256 MiB = 268435456 B):

   ```xml
   <qemu:commandline>
     <qemu:arg value="-device"/>
     <qemu:arg value='{"driver":"ivshmem-plain","id":"shmem0","memdev":"looking-glass"}'/>
     <qemu:arg value="-object"/>
     <qemu:arg value='{"qom-type":"memory-backend-file","id":"looking-glass","mem-path":"/dev/kvmfr0","size":268435456,"share":true}'/>
   </qemu:commandline>
   ```

5. **Shared folder (`virtiofs`):** Add a *Filesystem* device (`driver=virtiofs`)
   mapping e.g. `/home/measles/win-share` to target `win-share`.

## Inside Windows 11

1. Install the standard NVIDIA Windows driver, the VirtIO guest tools (for
   `virtiofs`, VirtIO-SCSI, and IVSHMEM), and the matching bleeding-edge signed
   **Looking Glass IDD** host package from `looking-glass.io` (bleeding-edge
   downloads matching the pinned master commit in `modules/vfio.nix`).
2. Remove the virtual QXL/VirtIO display (and dummy plug if used) so the Looking
   Glass IDD virtual monitor is the sole display.
3. Because `/etc/looking-glass-client.ini` sets `win:setGuestRes=yes`,
   `keepAspect=no`, and `forceAspect=no`, cycling column widths in Niri/Umbriel
   (`1/3`, `1/2`, `2/3`, `3/4`) automatically resizes Windows to match the tile
   with no letterboxing. Press `ScrollLock + =` anytime to force a manual sync.

## Daily usage

- **Start / view:** Launch **Windows 11** from your app launcher (`win11-launch`).
  It checks whether anything still holds the RTX 4090 open (notifying you with
  the process name if busy), starts `win11` if stopped, and opens Looking Glass.
- **Shut down:** Use Windows' Start menu, or right-click **Windows 11** in your
  launcher and pick **Shut Down Windows 11** (`win11-shutdown`). The hook
  returns the RTX 4090 to Linux automatically.
- **Linux gaming:** Launch games with `nvidia-offload <command>` (in Steam:
  `nvidia-offload %command%`, or set Vulkan/DXVK/VKD3D device selection so
  Steam stays on the iGPU while Proton/Vulkan games automatically use the 4090).
