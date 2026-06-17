# meta-mender-barebox

Mender A/B system updates on Yocto wrynose with the
[barebox](https://www.barebox.org/) bootloader, exercised in QEMU
(`qemuarm64`) and on real Raspberry Pi 4 hardware.

## Why this exists

Mender officially integrates with U-Boot and GRUB only; barebox is not
supported, and no community integration has ever been published. barebox does
have its own A/B mechanism (`bootchooser` + `state`), which is what RAUC uses —
but that is RAUC, not Mender. This layer instead makes barebox satisfy
*Mender's* bootloader contract directly, so the stock Mender `rootfs-image`
update module drives the A/B rollover unchanged.

## How it works

Mender's `rootfs-image` module only ever touches the boot decision through
libubootenv's `fw_setenv` / `fw_printenv`, reading and writing the variables
`mender_boot_part`, `upgrade_available`, `bootcount` and `bootlimit` in a
U-Boot-format environment. The trick here is that **barebox can read and write
that same U-Boot-format environment**: its `ubootvar` driver (device-tree node
`compatible = "barebox,uboot-environment"`) exposes the raw env partition, and
`ubootvarfs` presents it as a writable filesystem at `/dev/ubootvar0`.

The `ubootvar` driver is device-tree-only, and `barebox-dt-2nd` runs the
firmware-provided device tree (which has no place for our node), so the node is
added at runtime: `/env/boot/mender` runs `detect -a; of_overlay -l
/env/data/mender-bootenv.dtbo` (a compiled-in overlay) to patch the live tree
and probe the new device. The overlay references the env partition by its GPT
**partuuid** (`fixed-partitions` + `partuuid`, resolved globally via
`cdev_by_partuuid`), so it is independent of the storage controller / which
virtio node the disk lands on — identical for qemu and real hardware. Two
non-obvious requirements: `device-path` must be a **path string**
(`device-path = "/mender-bootenv-partitions/partition"`), not a `<&phandle>`
(`of_find_path` resolves it with `of_find_node_by_path`); and the env image size
**must equal the env partition size** (1 MiB), because `ubootvar` CRC-checks the
entire partition — a smaller `mkenvimage` size fails the CRC and the env is
silently treated as empty.

So there is **no shim** (unlike the systemd-boot and UKI demos in this repo):
the OS side is plain meta-mender plus stock `libubootenv-bin`, pointed at the
env partition by a one-line `/etc/fw_env.config`. The bootloader side is a
single barebox boot script, `/env/boot/mender`, that reimplements Mender's
U-Boot boot logic — `mender_setup` / `mender_altbootcmd` / `mender_try_to_recover`
— **including the bootcount increment** that U-Boot core would normally do via
`CONFIG_BOOTCOUNT`. On each boot it:

1. mounts the U-Boot env, reads the four variables;
2. if `upgrade_available=1`, increments `bootcount` and persists it *before*
   booting (so a hang or power-cut still counts);
3. if `bootcount > bootlimit`, switches `mender_boot_part` back to the other
   slot, clears `upgrade_available` and resets `bootcount` — the rollback;
4. mounts the selected rootfs slot (`/dev/<disk>.mender-rootfs{a,b}`) and boots
   its `/boot/Image` + DTB with `root=PARTLABEL=mender-rootfs{a,b}`.

A successful boot clears `upgrade_available` from userspace when Mender commits
the update (`fw_setenv upgrade_available 0`).

The kernel and DTB live inside each rootfs slot's `/boot`, so a Mender rootfs
Artifact carries the kernel for the slot it lands on — no separate kernel
staging is needed.

## Layout

| Partition | Label | Purpose |
|-----------|-------|---------|
| 1 | `mender-boot` | FAT boot/firmware (RPi firmware + `config.txt` + `barebox.img`; on qemu a barebox copy) |
| 2 | `mender-rootfsa` | rootfs slot A (kernel in `/boot`) |
| 3 | `mender-rootfsb` | rootfs slot B |
| 4 | `mender-data` | persistent `/data`, bind-mounted over `/var/lib/mender` |
| 5 | `mender-bootenv` | raw, non-redundant U-Boot env (read by barebox **and** libubootenv) |

## Running the qemuarm64 demo

barebox under `qemu -M virt` is loaded directly, so `runqemu` is not used (as
with the systemd-boot demo). After a build:

```
qemu-system-aarch64 -M virt -cpu cortex-a57 -m 2048 -nographic \
    -kernel tmp/deploy/images/qemuarm64/barebox-dt-2nd.img \
    -drive if=none,file=tmp/deploy/images/qemuarm64/<image>.wic,format=raw,id=hd0,cache=writethrough \
    -device virtio-blk-device,drive=hd0
```

barebox enumerates the disk as `virtioblk0`, reads the env, and boots the
selected slot to a Poky login.

## Status

Verified on **qemuarm64** (barebox 2026.04.0 from oe-core): clean boot of the
committed slot, and **rollback** — arming a trial on slot B with a broken rootfs
and power-cycling shows barebox count the boot attempts and, once `bootcount >
bootlimit`, switch `mender_boot_part` back to slot A, clear `upgrade_available`
and boot the good slot (`mender: bootlimit exceeded, rolling back to part 2`).

To reproduce the rollback without a server: write an "armed" env to the
`mender-bootenv` partition (`mender_boot_part=3, upgrade_available=1,
bootcount=0, bootlimit=1`) with `mkenvimage -s 0x100000`, corrupt slot B, and
boot twice on a **persistent** (non-snapshot) disk.

On **Raspberry Pi 4** (real hardware), the whole integration mechanism is proven:
the GPU firmware loads `barebox.img` (needs `kernel=barebox.img` + **`arm_64bit=1`**
in config.txt, since overriding `kernel=` loses the `kernel8.img` 64-bit
auto-detect), barebox reads the env via `ubootvar`/partuuid, `/env/boot/mender`
selects the slot (SD is `disk0`, not `mmc1`), mounts the rootfs, and **starts the
kernel**. Two RPi-specific knobs are set in the kas wrapper: `BAREBOX_MENDER_DTB_SOURCE
= "internal"` (boot barebox's own VideoCore-derived tree, like a normal RPi boot,
rather than forcing the slot's static dtb) and `core_freq=250` (pins the mini-UART
baud — otherwise RPi4's variable core clock doubles it and the console is garbled
at 115200 / readable at 230400).

**Known limitation (RPi4):** the RPi *downstream* kernel currently hangs early
(~0.9 s, before rootfs mount) on the device tree barebox hands it, so it does not
yet reach userspace — a barebox + downstream-RPi-kernel/dtb platform issue, separate
from the (hardware-proven) Mender+barebox mechanism. Resolving it needs deeper
work (compare the barebox-passed dtb against a known-good RPi4 boot dtb around the
PCIe/USB/clock init, try a mainline kernel+dtb, or adjust barebox's RPi board
fixups), not a bootarg tweak.

See the matching kas wrappers `qemuarm64-barebox.yml` and
`raspberrypi4-64-barebox.yml` in mender-community-images at branch
`wrynose-demos`.
