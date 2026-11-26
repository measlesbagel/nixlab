# Windows VM with dynamic VFIO on chilense

`chilense` keeps its Linux desktop on the Ryzen 7 7800X3D iGPU (`0000:0c:00.0`)
so the RTX 4090 (`0000:01:00.0`) can serve Linux games via `nvidia-offload` and
dynamically unbind to `vfio-pci` when the Windows 11 scanning VM starts
(`modules/vfio.nix`). Looking Glass streams the VM into a native Linux window
over `/dev/kvmfr0`.

## Physical wiring (ROG Strix B650E-I + PG32UCDM)

- **Monitor -> motherboard DP-Alt USB-C (10 Gbps, DP icon):** Use a USB-C to
  DisplayPort 1.4 cable, or a USB-C to USB-C cable with the PG32UCDM set to
  **USB 2.0 / 4-lane DP** mode so DP 1.4 + DSC reaches 4K @ 240 Hz. Do not use
  the motherboard HDMI port (`amdgpu` caps HDMI at 2.0 / 4K @ 60 Hz on Linux).
- **DisplayPort dummy plug -> RTX 4090:** Provides the virtual monitor head
  that Looking Glass captures inside Windows.
- **RTL8159 10GbE adapter -> motherboard 20 Gbps USB-C:** Unchanged.

## Creating the `win11-scan` VM

Create a Windows 11 guest named `win11-scan` in `virt-manager` (the dynamic GPU
hook matches `homelab.vfio.vmNames`):

1. **Chipset & firmware:** Q35 with UEFI Secure Boot (OVMF) and emulated
   TPM 2.0 (`swtpm`).
2. **CPU & memory:** Pin 8–12 host threads (`host-passthrough`) and allocate
   16–32 GiB RAM. Enable shared memory backing under *Memory* (required for
   `virtiofs`).
3. **PCI host devices (pass both GPU functions together):**
   - `0000:01:00.0` (RTX 4090 VGA) and `0000:01:00.1` (RTX 4090 Audio) —
     IOMMU group 12.
   - Optional scanner connectivity (each is in its own IOMMU group, so libvirt
     manages detach/reattach automatically):
     - `0000:09:00.0` — onboard MediaTek MT7922 Wi-Fi 6E (IOMMU group 19; leaves
       host Bluetooth on `0a:00.0` untouched) for wireless Bambu S1 scanning.
     - `0000:0c:00.4` — empty CPU USB 3.1 10 Gbps controller (IOMMU group 26)
       for wired USB scanning or a Wi-Fi 6 USB dongle.
4. **Looking Glass IVSHMEM device (`/dev/kvmfr0`):** Add the `qemu` XML
   namespace (`xmlns:qemu="http://libvirt.org/schemas/domain/qemu/1.0"`) to
   `<domain>` via `virsh edit win11-scan`, and add this `<qemu:commandline>`
   block (matching `homelab.vfio.kvmfrSizeMb`, default 128 MiB = 134217728 B):

   ```xml
   <qemu:commandline>
     <qemu:arg value="-device"/>
     <qemu:arg value='{"driver":"ivshmem-plain","id":"shmem0","memdev":"looking-glass"}'/>
     <qemu:arg value="-object"/>
     <qemu:arg value='{"qom-type":"memory-backend-file","id":"looking-glass","mem-path":"/dev/kvmfr0","size":134217728,"share":true}'/>
   </qemu:commandline>
   ```

5. **Shared scan folder (`virtiofs`):** Add a *Filesystem* device (`driver=virtiofs`)
   mapping e.g. `/home/measles/scans` to target `scans` so exported meshes land
   directly on Linux for Bambu Studio / CAD.

## Inside Windows 11

1. Install the standard NVIDIA Windows driver, the VirtIO guest tools (for
   `virtiofs` and IVSHMEM), and the **Looking Glass Host** service (matching
   client version `B7`).
2. Once Windows outputs to the DP dummy plug, remove the virtual QXL/VirtIO
   display (or set the DP dummy plug as the sole display) and connect from
   Linux with:

   ```console
   looking-glass-client
   ```

## Daily usage

- **Linux gaming:** Launch games with `nvidia-offload <command>` (in Steam:
  `nvidia-offload %command%`). Close any app using the 4090 before starting
  `win11-scan`; the hook aborts cleanly and lists the PID if anything still
  holds `/dev/nvidia*` open.
- **3D scanning:** Start `win11-scan` from `virt-manager` (or
  `virsh start win11-scan`) and run `looking-glass-client`. Shutting down the
  VM returns the 4090 to Linux automatically.
