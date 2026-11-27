# Dynamic VFIO & Looking Glass on chilense

`chilense` keeps its Linux desktop on the Ryzen 7 7800X3D iGPU (`0000:0c:00.0`)
so the RTX 4090 (`0000:01:00.0`) can serve Linux games via `nvidia-offload` and
dynamically unbind to `vfio-pci` when the `win11` VM starts (`modules/vfio.nix`).
Looking Glass (pinned master build with signed IDD + `win:setGuestRes=yes`)
streams the VM into a resizable Wayland window over `/dev/kvmfr0`.

Declarative VM definition (`NixVirt`) and Windows guest provisioning (`fetchurl`
+ `winget configure` YAML) will land in a follow-up once hardware passthrough is
verified on `chilense`.

## Physical wiring (ROG Strix B650E-I + PG32UCDM)

- **Monitor -> motherboard DP-Alt USB-C (10 Gbps, DP icon):** Use a USB-C to
  DisplayPort 1.4 cable, or a USB-C to USB-C cable with the PG32UCDM set to
  **USB 2.0 / 4-lane DP** mode so DP 1.4 + DSC reaches 4K @ 240 Hz. Do not use
  the motherboard HDMI port (`amdgpu` caps HDMI at 2.0 / 4K @ 60 Hz on Linux).
- **DisplayPort dummy plug -> RTX 4090:** Optional once the signed Looking Glass
  IDD is installed inside Windows; handy during initial driver bring-up.
- **RTL8159 10GbE adapter -> motherboard 20 Gbps USB-C:** Unchanged.

## Host hardware & storage layout

- **IOMMU groups verified on `chilense`:**
  - Group 12 (`0000:01:00.0`, `0000:01:00.1`): RTX 4090 VGA + HDA audio
    (pass with `managed='no'` so the `vfio-gpu` hook handles unbind/ReBAR/rebind).
  - Group 19 (`0000:09:00.0`): onboard MediaTek MT7922 Wi-Fi 6E (optional
    `managed='yes'` passthrough; host Bluetooth stays on `0a:00.0`).
  - Group 26 (`0000:0c:00.4`): empty CPU USB 3.1 10 Gbps controller (optional
    `managed='yes'` passthrough).
- **VM storage (`hosts/chilense/disko.nix`):** `/var/lib/libvirt/images` is its
  own `@vms` btrfs subvolume (`+C` NoCoW via tmpfiles, excluded from btrbk
  snapshots/replication). Use a thin-provisioned `qcow2` (e.g. 500 GiB) with
  VirtIO-SCSI + `discard='unmap'`, and keep shared work files on `@home` via
  `virtiofs`.
- **Looking Glass IVSHMEM (`/dev/kvmfr0`, 256 MiB = 268435456 B):**

  ```xml
  <qemu:commandline>
    <qemu:arg value="-device"/>
    <qemu:arg value='{"driver":"ivshmem-plain","id":"shmem0","memdev":"looking-glass"}'/>
    <qemu:arg value="-object"/>
    <qemu:arg value='{"qom-type":"memory-backend-file","id":"looking-glass","mem-path":"/dev/kvmfr0","size":268435456,"share":true}'/>
  </qemu:commandline>
  ```

## Daily usage

- **Start / view:** Launch **Windows 11** from your app launcher (`win11-launch`).
  It checks whether anything holds the RTX 4090 open (notifying with the process
  name if busy), starts `win11` if stopped, and opens Looking Glass.
- **Dynamic resize on Niri/Umbriel:** `/etc/looking-glass-client.ini` sets
  `win:setGuestRes=yes`, `keepAspect=no`, and `forceAspect=no`. With the signed
  Looking Glass IDD installed in Windows (`looking-glass-idd-setup.exe /S /ivshmem`),
  cycling column widths (`1/3`, `1/2`, `2/3`, `3/4`) resizes the guest display
  automatically. Press `ScrollLock + =` to force a manual sync.
- **Shut down:** Use Windows' Start menu, or right-click **Windows 11** in your
  launcher and pick **Shut Down Windows 11** (`win11-shutdown`). The hook
  returns the RTX 4090 to Linux automatically.
