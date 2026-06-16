# meta-mender-systemd-boot

Mender A/B updates for systems that boot via **stock, unpatched systemd-boot**,
using systemd's native [Automatic Boot
Assessment](https://www.freedesktop.org/software/systemd/man/latest/systemd-bless-boot.service.html)
(boot counting) for in-firmware rollback. Yocto wrynose, end-to-end verified
against hosted.mender.io on `qemux86-64`.

## Why a dedicated layer

meta-mender does ship a `mender-systemd-boot` feature, but it predates modern
systemd: it carries a downstream patch that bolts an A/B state machine into
`systemd-boot` itself (`slot.c`), and it builds the per-slot kernels as
meta-intel `uefi-comboapp` combo apps. That `uefi-comboapp` class has since been
removed from meta-intel, so the stock pathway no longer composes on wrynose.

This layer takes the opposite approach: it leaves systemd-boot completely
unpatched and uses the boot-assessment mechanism systemd already provides. A/B
slot selection and rollback are expressed entirely through on-ESP files — boot
loader entries whose filenames carry a tries-left counter — so nothing in the
boot path is Mender- or downstream-specific.

It is also distinct from the other two systemd-boot-adjacent demos in this
repository:

* `meta-mender-uki` boots Unified Kernel Images and has **no** firmware
  rollback — it only rewrites the `default` line in `loader.conf`;
* `meta-mender-efibootmgr` selects the slot through UEFI `BootNext`/`BootOrder`
  variables.

Here the slots are classic [Type #1 Boot Loader
Specification](https://uapi-group.org/specifications/specs/boot_loader_specification/)
entries and the rollback is systemd-boot's own boot counting.

## How the A/B switch works

The ESP is mounted at `/boot/efi`. Each rootfs slot has a boot entry on it:

```
/boot/efi/loader/entries/mender-a.conf  ->  /EFI/Linux/mender-a/{bzImage,initrd}, root=PARTLABEL=mender-rootfsa
/boot/efi/loader/entries/mender-b.conf  ->  /EFI/Linux/mender-b/{bzImage,initrd}, root=PARTLABEL=mender-rootfsb
```

There is **no `default` in `loader.conf`**. Selection is driven by the entries'
`version` field: systemd-boot boots the highest-versioned entry that is not
"bad". The shim hands the trial slot a higher version than the committed slot,
so the trial is preferred while it is healthy.

On an update the `mender-sdboot-shim` (a `fw_setenv`/`fw_printenv` drop-in)
does, in `ArtifactInstall`:

1. mounts the freshly-written inactive slot and copies that slot's
   `/usr/lib/mender/{bzImage,initrd}` (which travel with the Mender rootfs
   artifact) onto the ESP, so a kernel update propagates with the rootfs;
2. writes the slot's entry with a boot counter in the filename and a bumped
   version, e.g. `mender-b+1-0.conf` ("1 try left, 0 done").

systemd-boot decrements that counter by renaming the file each time it selects
the entry (`+1-0` → `+0-1`). When `tries-left` reaches zero the entry is "bad"
and is sorted after all non-bad entries, so the firmware boots the still-good
committed slot instead. **That is the rollback — in firmware, with no patch and
no EFI-variable writes.**

On `ArtifactCommit` the shim strips the counter from the committed slot's entry
(`mender-b+0-1.conf` → `mender-b.conf`), the file-level equivalent of
`systemd-bless-boot good`; the slot is now permanently good and keeps its high
version, so it stays the default.

If a trial panics or is power-cycled before commit, it counts out and the
firmware falls back to the committed slot; Mender's `ArtifactVerifyReboot` then
sees that the running slot is not the one it intended and reports the
deployment as a failure.

## What this layer provides

* `classes/mender-systemd-boot-ab.bbclass` — stages each slot's kernel + initrd
  onto the ESP under `/EFI/Linux/mender-{a,b}/`, writes the two BLS entries
  (slot A version 1, slot B version 0, so A is the initial default) and a
  `loader.conf` with only a timeout, stages the kernel + initrd into the rootfs
  at `/usr/lib/mender/`, writes the fstab (ESP at `/boot/efi`), and — because
  `mender-image` is disabled — seeds `/data/mender` and a bootstrap artifact so
  the device reports its `artifact_name`.

* `recipes-bsp/mender-sdboot-shim/` — the shim described above, installed as
  `/usr/bin/mender-sdboot-shim` with `fw_setenv`/`fw_printenv` symlinked to it.
  It also ships a tmpfiles snippet + a `var-lib-mender.mount` unit that
  bind-mount `/data/mender` over `/var/lib/mender` so the Mender state DB and
  agent key survive the rootfs swap, and it masks systemd's automatic
  `systemd-bless-boot.service` so a trial is only ever blessed by Mender's
  commit.

* `recipes-kernel/linux/` — AHCI, ext4, vfat, virtio-net and the EFI stub built
  into the kernel.

* `files/wic/mender-systemd-boot-qemux86-64.wks.in` — a four-partition GPT
  layout: 256 MB ESP, two 1 GB rootfs slots (`mender-rootfsa`,
  `mender-rootfsb`) and a 64 MB data partition, on an AHCI disk.

## Runtime quirks worth knowing

Each of these cost a build/deploy cycle to find; they are the reason the layer
is shaped this way.

1. **Selection is by `version`, not `default`.** An explicit `default` in
   `loader.conf` pins a slot even after it has counted out, which defeats the
   rollback. Letting boot counting + the `version` field choose is what makes a
   bad trial fall back to the committed slot.

2. **One ESP mount at `/boot/efi`, not two.** meta-mender mounts the boot
   partition at `MENDER_BOOT_PART_MOUNT_LOCATION`, which defaults to `/boot/efi`,
   and wic emits a UUID fstab entry for the ESP at its wks mountpoint. If those
   two mountpoints differ (e.g. wks `/boot` vs meta-mender `/boot/efi`), the FAT
   ESP is mounted twice and — because FAT is case-insensitive — the `/boot/efi`
   mount shadows the `/boot/EFI` directory, so the shim's kernel writes never
   reach the ESP root systemd-boot reads and the slot flip silently fails. The
   wks therefore mounts the ESP at `/boot/efi` (matching meta-mender) and the
   shim uses `/boot/efi`, giving a single, unambiguous mount.

3. **Fresh read of the just-installed slot.** On a flip the shim mounts the
   inactive slot (just written by Mender as raw block writes) to copy its new
   kernel onto the ESP. It `blockdev --flushbufs` + drops caches first, else the
   mount can return the slot's *previous* contents and stage the old kernel —
   invisible when the kernel is unchanged, but it would defeat the rollback test
   (the deliberately-broken kernel must actually reach the ESP).

4. **The shim runs under busybox.** `fw_printenv`/`fw_setenv` are POSIX shell;
   keep to busybox-compatible options (`head -n 1`, not `head -1`).

5. **`fw_setenv -s -` batch mode.** Mender commits the A/B variables by piping
   `key value` lines into `fw_setenv -s -`; the shim handles that explicitly and
   acts once, after the whole batch is applied.

6. **Canary pre-seed.** The rootfs-image update module aborts under `set -e` if
   `fw_printenv mender_check_saveenv_canary` is undefined, so the shim pre-seeds
   both canary variables.

7. **Mender state on the data partition.** `mender-image` is disabled, so the
   `/var/lib/mender` → `/data/mender` bind mount above is what keeps the
   deployment record and agent key across the slot swap; without it the
   post-reboot commit cannot resume.

## Boot chain

```
QEMU
  -> OVMF (UEFI firmware)
  -> systemd-boot (EFI/BOOT/BOOTX64.EFI, firmware removable-media fallback)
  -> Type #1 boot entry (systemd-boot EFI stub loads bzImage + initrd)
  -> kernel  (root=PARTLABEL=mender-rootfs{a,b})
```

A fresh device has no Mender boot entry in NVRAM, so the first boot reaches
systemd-boot through the firmware's `\EFI\BOOT\BOOTX64.EFI` fallback. An AHCI
disk is used because OVMF does not re-enumerate virtio across a guest reboot.

## Reproducing the build

This layer is consumed by the kas wrapper at
`yocto/wrynose/floating/qemux86-64-systemd-boot.yml` on branch `wrynose-demos`
of `theyoctojester/mender-community-images`:

```sh
git clone https://github.com/theyoctojester/mender-community-images.git
cd mender-community-images
git checkout wrynose-demos
kas build yocto/wrynose/floating/qemux86-64-systemd-boot.yml
```

## Running in QEMU

`runqemu` cannot drive the pflash-OVMF + AHCI setup, so launch QEMU directly
(the wic, OVMF code and a writable copy of the OVMF vars):

```sh
DEPLOY=build/tmp/deploy/images/qemux86-64
QEMU=$DEPLOY/../../../work/x86_64-linux/qemu-helper-native/*/recipe-sysroot-native/usr/bin/qemu-system-x86_64

cp $DEPLOY/core-image-minimal-qemux86-64-systemd-boot.wic /tmp/test.wic
cp $DEPLOY/ovmf.vars.qcow2 /tmp/ovmf-vars.qcow2

$QEMU \
  -device virtio-net-pci,netdev=net0,mac=52:54:00:12:35:04 \
  -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2224-:22 \
  -drive id=disk0,file=/tmp/test.wic,format=raw,if=none -device ide-hd,drive=disk0 \
  -cpu Skylake-Client -machine q35,i8042=off -smp 4 -m 2048 \
  -serial mon:stdio -nographic \
  -drive if=pflash,format=qcow2,file=$DEPLOY/ovmf.code.qcow2,readonly=on \
  -drive if=pflash,format=qcow2,file=/tmp/ovmf-vars.qcow2
```

## Verification

Verified end-to-end on `qemux86-64` against hosted.mender.io:

* **First boot** lands on slot A (`mender-rootfsa`), `version 1` winning over
  slot B's `version 0`.
* **Success:** a `release-2` rootfs-image OTA streams to slot B, the shim arms
  `mender-b+1-0.conf`, systemd-boot decrements the counter and trial-boots slot
  B, `ArtifactCommit` strips the counter, and the server reports the deployment
  finished with the device on slot B reporting `artifact_name=release-2`.
* **Rollback:** a deliberately broken artifact whose trial kernel will not load
  is armed on the inactive slot; systemd-boot counts it out, the firmware boots
  the still-good committed slot, `ArtifactVerifyReboot` detects the slot
  mismatch, and the server reports the deployment as failed with the device
  still on its committed slot and original `artifact_name`.

## License

`meta-mender-systemd-boot/LICENSE` (Apache-2.0). Individual recipes specify
their own `LICENSE` per Yocto convention.
