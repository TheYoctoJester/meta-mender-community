# meta-mender-uki

Mender A/B updates for systems that boot via systemd-boot from a [Unified
Kernel Image](https://uapi-group.org/specifications/specs/unified_kernel_image/)
(UKI) on Yocto wrynose. End-to-end verified against hosted.mender.io on
`qemuarm64-secureboot` from meta-arm.

## Why a dedicated layer

`mender-image-systemd-boot.bbclass` in meta-mender still `inherit`s the
`uefi-comboapp` class from meta-intel; that predates `ukify` and the
oe-core `uki.bbclass`, and won't compose with it. `meta-mender-uki`
replaces that pathway end-to-end without touching meta-mender itself.

## What this layer provides

* `classes/uki-mender-ab.bbclass` — runs `ukify` twice to produce
  `uki-a.efi` (with `root=PARTLABEL=mender-rootfsa` baked in) and
  `uki-b.efi` (with `root=PARTLABEL=mender-rootfsb`), deploys both onto
  the ESP at `/EFI/Linux/`, writes an initial `loader.conf` that names
  `uki-a.efi` as the default, and also stages copies of both UKIs into
  `${IMAGE_ROOTFS}/usr/lib/mender/` so a single Mender artifact carries
  the kernel for both slots in lockstep with the rootfs.

* `recipes-bsp/mender-uki-shim/` — a small POSIX-shell shim installed as
  `/usr/bin/mender-uki-shim`, with `fw_setenv` and `fw_printenv` as
  symlinks to it. Persists Mender's A/B state at
  `/data/mender-uki/state` (deliberately on the data partition, not the
  rootfs, so values set by the mender client pre-reboot survive the
  rootfs swap). On `fw_setenv mender_boot_part=<N>` it copies the
  matching UKI from `/usr/lib/mender/` to the ESP and rewrites the
  `default` line in `/boot/loader/loader.conf`. Also handles the
  `fw_setenv -s -` batch form (which the rootfs-image update module
  uses).

  The recipe additionally ships:
  * `/usr/lib/tmpfiles.d/mender-uki-data.conf` — on first boot, copies
    `/var/lib/mender`'s build-time content into `/data/mender`.
  * `/lib/systemd/system/var-lib-mender.mount` — bind-mounts
    `/data/mender` over `/var/lib/mender` before the mender services
    start. This is what makes the mender state DB and the generated
    agent key survive the rootfs swap of an A/B OTA; without it,
    post-reboot mender has no record of the deployment in progress and
    the server reports `Failure` even though the bit-level swap was
    correct.

* `files/wic/efi-uki-mender-bootdisk.wks.in` — a four-partition GPT
  layout for the demo: 256 MB ESP, two 1 GB rootfs slots
  (`mender-rootfsa`, `mender-rootfsb`), and a 64 MB data partition
  (`mender-data`).

## Four runtime quirks worth knowing

Each cost a build/deploy cycle to discover. They're the entire reason
the layer is shaped this way:

1. **Canary pre-seed.** The mender rootfs-image update module runs with
   `set -e` and aborts if `fw_printenv mender_check_saveenv_canary`
   exits non-zero. The shim's `init_state` therefore pre-seeds both
   `mender_check_saveenv_canary=1` and `mender_saveenv_canary=1` rather
   than leaving them undefined.

2. **`fw_setenv -s` batch mode.** Mender invokes `fw_setenv -s -` with
   multiple `key value` lines on stdin to commit several variables at
   once. The shim handles that explicitly; without it, the literal arg
   pair `-s -` is written as a single bogus state line and the actual
   variables are dropped.

3. **Bind `/var/lib/mender` from the data partition.** Mender's state
   DB lives at `/var/lib/mender`; an A/B rootfs OTA overwrites it. The
   tmpfiles snippet + mount unit above keep the deployment record and
   `mender-agent.pem` persistent across slot swaps, which is what
   actually lets the server see `Success` instead of `Failure` on the
   post-reboot commit.

4. **ESP sizing.** The `qemuarm64-secureboot` machine config stages a
   copy of the kernel `Image` to the ESP via `IMAGE_BOOT_FILES` (unused
   at runtime — the UKI carries the kernel — but harmless to leave).
   With two ~40 MB UKIs plus the kernel image, the previously-tried
   128 MB ESP filled up and the shim's `cp uki-b.efi …` failed with
   ENOSPC. The wks now reserves 256 MB.

## Reproducing the build

This layer is consumed by the matching kas wrapper at
`yocto/wrynose/floating/qemuarm64-uki.yml` on branch `wrynose-demos` of
`theyoctojester/mender-community-images`:

```sh
git clone https://github.com/theyoctojester/mender-community-images.git
cd mender-community-images
git checkout wrynose-demos
kas build yocto/wrynose/floating/qemuarm64-uki.yml
```

The kas wrapper pins the meta-mender-community fork at this branch and
inherits the rest of the wrynose stack (oe-core, meta-yocto,
meta-openembedded, meta-arm, meta-mender) from the existing
`include/mender-full.yml` and `include/arm.yml`.

## Boot chain

```
QEMU
  -> trusted-firmware-a (flash.bin from meta-arm)
  -> U-Boot UEFI runtime
  -> systemd-boot   (from oe-core; reads /boot/loader/loader.conf)
  -> uki-{a,b}.efi  (systemd-stub + kernel + initramfs + signed cmdline)
  -> kernel
```

On `qemuarm64-secureboot` the U-Boot UEFI runtime cannot persist EFI
variables to flash, so `bootctl set-default` (which writes
`LoaderEntryDefault`) is best-effort only. The durable mechanism is the
`default` line in `/boot/loader/loader.conf`, which is what the shim
rewrites on slot flip.

## Verification recipe

After `kas build` completes, boot the wic in QEMU:

```sh
kas shell yocto/wrynose/floating/qemuarm64-uki.yml \
    -c "runqemu qemuarm64-secureboot nographic serial wic slirp"
```

Inside the guest, the following should all hold:

```sh
mount | grep ' / '                                      # /dev/vda2  (slot A)
mount | grep /var/lib/mender                            # bind mount from /dev/vda4
ls /usr/lib/mender/uki-*.efi                            # both UKIs staged
cat /boot/loader/loader.conf                            # default uki-a.efi
fw_printenv mender_boot_part                            # 2
```

For the full end-to-end OTA recipe against hosted.mender.io (upload an
artifact, accept the device, deploy, observe the slot swap, server
reports Success), see the project's local NOTE.txt at
`https://github.com/<your>/<your-build-tree>` or the matching section in
this branch's commit history.

## License

`meta-mender-uki/LICENSE` (Apache-2.0). Individual recipes specify their
own `LICENSE` per Yocto convention.
