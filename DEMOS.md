# Wrynose Mender demo layers

This branch (`wrynose-demos`) carries a set of demo layers that each show a
different way to do Mender A/B OTA updates on the Yocto **wrynose** release. They
fall into two families.

The kas configurations that drive them live in **mender-community-images** under
`yocto/wrynose/floating/`, and they are built/tested by the
`build-yocto-wrynose-demo.yml` workflow in **mender-integration-builds**.

CI coverage levels referenced below:

- **build** — the image compiles on the wrynose stack.
- **boot-smoke** — built image is booted in-job under `runqemu` to a login prompt.
- **OTA** — full round-trip against hosted.mender.io (deploy → reboot → commit).
- **qemu A/B test** — separate QEMU test job (OVMF) exercising the slot switch.
- **hardware** — flashed and tested on a physical DUT in the lab rig.

---

## Family A — the bootloader/firmware owns A/B

Mender's `rootfs-image` update module owns the A/B rootfs; the bootloader or
firmware performs slot selection and rollback. `mender-image` / `mender-part-
images` are off and an explicit `.wks` owns the partition layout.

The QEMU/x86 members (uki, systemd-boot, efibootmgr, x86 U-Boot EFI, barebox)
share the common feature skeleton in `mender-community-images`'
`yocto/wrynose/floating/include/mender-explicit-ab.yml` and add only their
bootloader-specific delta. The efibootmgr and x86 U-Boot EFI demos additionally
use the `/data`-persistence helper `mender-data-persist` (in
`meta-mender-demos-common`). The two barebox demos share a single parameterised
disk layout, `meta-mender-barebox/files/wic/mender-barebox.wks.in`, selected per
board via `MENDER_BAREBOX_ONDISK` / `MENDER_BAREBOX_ALIGN`. The Raspberry Pi
tryboot demo predates that consolidation and carries its own configuration.

| Demo | Layer | Board (kas config) | Slot-selection mechanism | CI |
|------|-------|--------------------|--------------------------|----|
| UKI | `meta-mender-uki` | `qemuarm64-uki` | systemd-boot Boot Loader Spec + boot counting on Unified Kernel Images | build + OTA (verified run #2443) |
| systemd-boot | `meta-mender-systemd-boot` | `qemux86-64-systemd-boot` | stock systemd-boot Type #1 BLS entries + automatic boot assessment | build + qemu A/B test (run #2443) |
| efibootmgr | `meta-mender-efibootmgr` | `qemux86-64-efibootmgr` | UEFI boot manager `BootNext`/`BootOrder` (custom Update Module) | build + qemu A/B test (run #2443) |
| x86 U-Boot EFI | `meta-mender-x86-uboot-efi` (+ `meta-mender-explicit-wic`) | `qemux86-64-uboot-efi` | U-Boot run as an EFI application under OVMF (GPLv3-free chain) | build + qemu A/B test (run #2443) |
| FWU | `meta-mender-fwu` | `qemuarm64-fwu` | U-Boot FWU multi-bank metadata + EFI capsule-on-disk | build + OTA (verified run #2443) |
| barebox | `meta-mender-barebox` | `qemuarm64-barebox`, `raspberrypi4-64-barebox` | barebox reads the U-Boot-format env (rootfs-image module drives it, no shim) | build only — runtime unverified (WIP) |
| Raspberry Pi tryboot | `meta-mender-raspberrypi-tryboot` | `raspberrypi4-64-tryboot`, `raspberrypi5-tryboot` (+ `-validation`) | Raspberry Pi firmware `tryboot` / `autoboot.txt` | build + hardware (run #2443) |

`meta-mender-explicit-wic` is the original explicit-WIC base demo (mender-uboot +
explicit `.wks` + a minimal `.mender` artifact writer). It has no standalone kas
config; the x86 U-Boot EFI demo builds on it.

---

## Family B — an external updater owns the rootfs

A third-party updater owns the rootfs; the Mender client runs in **client-
only** mode (`meta-mender-client-only`) and a custom Update Module hands the
payload to that updater. `mender-full` is off. The
`version-inventory-script` do_package QA workaround for wrynose lives once in
`meta-mender-client-only`'s `mender_%.bbappend`. Most of these use an A/B
rootfs; OSTree instead keeps a single rootfs and switches between OSTree
deployments.

| Demo | Layer | Board (kas config) | How the payload is applied | CI |
|------|-------|--------------------|----------------------------|----|
| RAUC | `meta-mender-rauc` | `qemuarm64-rauc`, `raspberrypi4-64-rauc` | a `rauc` Update Module installs a `.raucb` bundle carried in a Mender artifact; RAUC owns the slots | build + boot-smoke (qemu); build + hardware OTA (RPi4, dut1) — verified run #2443 |
| SWUpdate | `meta-mender-swupdate` | `qemuarm64-swupdate` | a `swu` Update Module streams a `.swu` into the SWUpdate daemon over IPC (no disk staging) | build + OTA (verified run #2443) |
| OSTree | `meta-mender-ostree` | `qemuarm64-ostree` | an `ostree` Update Module applies an OSTree static delta (`apply-offline`) then `ostree admin deploy`; OSTree owns the atomic deployment switch and rollback (no A/B partitions) | build + OTA (verified run #2443) |

---

## Shared / support layers

- **`meta-mender-demos-common`** — building blocks shared by several demos.
  Currently `mender-data-persist` (seed `/data/mender` + bind-mount it over
  `/var/lib/mender` so Mender state survives an A/B rootfs swap), used by the
  efibootmgr and x86 U-Boot EFI demos.
- **`meta-mender-client-only`** — the Mender client in client-only mode, used by
  the Family B demos.
- **`meta-mender-explicit-wic`** — see Family A.
