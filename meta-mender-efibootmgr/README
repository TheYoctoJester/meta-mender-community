meta-mender-efibootmgr
======================

Demo layer for Mender A/B updates on x86-64 where the UEFI boot manager itself
is the slot selector. The firmware launches an EFI-stub kernel directly -- no
GRUB, no U-Boot, no systemd-boot -- and a custom Mender Update Module switches
between the A and B rootfs slots with efibootmgr.

Note that efibootmgr is not a bootloader and meta-mender ships no efibootmgr
integration; this is a from-scratch A/B mechanism built on top of the UEFI boot
variables, in the spirit of the other experimental layers in this repository.

Why a custom Update Module
==========================

Mender's stock A/B flow needs a bootloader integration (mender-grub or
mender-uboot) whose environment the rootfs-image module reads and writes to pick
the active slot. This demo has no such environment: slot selection lives in UEFI
boot variables. So mender-grub / mender-uboot / mender-bios / mender-image /
mender-part-images are all disabled, an explicit WKS file lays out the disk, and
a custom 'efibootmgr-rootfs' Update Module performs the A/B switch. The artifact
is built out of band (make-artifact.sh) as a module-image of that type.

How the A/B switch works
========================

Two persistent UEFI boot entries are created once on first boot:

  "Mender slot A" -> \EFI\mender-a\bzImage.efi  -u root=PARTUUID=<rootA>
  "Mender slot B" -> \EFI\mender-b\bzImage.efi  -u root=PARTUUID=<rootB>

  - BootOrder holds the committed slot (the default).
  - On update, the module writes the inactive slot, copies that rootfs's
    /boot/bzImage onto the ESP for the inactive slot, and sets BootNext to the
    inactive slot's entry.
  - BootNext is a one-shot override: the firmware deletes it before handing
    control to the trial kernel. So a trial that panics, hangs, or loses power
    falls back to BootOrder -- the still-committed slot -- on the next boot.
    That is the rollback, and it needs no bootcount.
  - ArtifactCommit rewrites BootOrder to make the new slot the default.
  - ArtifactRollback clears any BootNext and points BootOrder back at the
    previously-committed slot.

First boot and the firmware fallback
====================================

A fresh device has no Mender boot entries in NVRAM, so the very first boot
reaches Linux through the firmware's removable-media fallback,
\EFI\BOOT\bootx64.efi. That launch carries no load options, so the EFI stub
uses the kernel's builtin CONFIG_CMDLINE, which names rootA by PARTUUID. The
rootA/rootB partitions therefore use fixed PARTUUIDs (see conf/layer.conf and
the wic file). The first-boot service then registers the two per-slot entries,
which pass each slot's root= via efibootmgr -u; on x86 the load-option command
line is appended after the builtin one and the last root= wins, so the per-slot
entries take precedence over the builtin rootA default.

Dependencies
============

  URI: git://git.openembedded.org/openembedded-core.git
  layers: meta
  branch: wrynose

  URI: git://git.openembedded.org/bitbake.git
  branch: wrynose

  URI: git://git.yoctoproject.org/git/meta-yocto.git
  layers: meta-poky, meta-yocto-bsp
  branch: wrynose

  URI: git://git.openembedded.org/meta-openembedded
  layers: meta-oe
  branch: wrynose

  URI: https://github.com/mendersoftware/meta-mender.git
  layers: meta-mender-core
  branch: wrynose

Contributions
=============

Please see the README file in the top level directory.

Maintainer: Josef Holzmayr <jester@theyoctojester.info>

Usage
=====

Build the demo image (kas build config in the mender-community-images repo,
branch wrynose-demos):

  kas build yocto/wrynose/floating/qemux86-64-efibootmgr.yml

Boot chain
==========

  QEMU -> OVMF (UEFI firmware) -> EFI-stub bzImage (selected by BootNext/BootOrder) -> Linux

Partition layout (GPT, SATA/AHCI disk):

  1. ESP   (64 MB, FAT)  - EFI/BOOT/bootx64.efi, EFI/mender-a/bzImage.efi,
                           EFI/mender-b/bzImage.efi
  2. rootA (512 MB, ext4) - active rootfs, fixed PARTUUID
  3. rootB (512 MB, ext4) - inactive rootfs (for A/B updates), fixed PARTUUID
  4. data  (128 MB, ext4) - persistent /data (Mender state, growfs target)

Running in QEMU
===============

runqemu cannot produce the correct command line for this setup (it lacks pflash
OVMF support and IDE/AHCI drive selection). Launch QEMU manually instead:

  DEPLOY=build/tmp/deploy/images/qemux86-64
  QEMU=$DEPLOY/../../../work/x86_64-linux/qemu-helper-native/1.0/recipe-sysroot-native/usr/bin/qemu-system-x86_64

  cp $DEPLOY/mender-efibootmgr-image-qemux86-64-efibootmgr.wic /tmp/test.wic
  cp $DEPLOY/ovmf.vars.qcow2 /tmp/ovmf-vars.qcow2

  $QEMU \
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:35:02 \
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
    -drive id=disk0,file=/tmp/test.wic,format=raw,if=none \
    -device ide-hd,drive=disk0 \
    -cpu Skylake-Client -machine q35,i8042=off -smp 4 -m 2048 \
    -serial mon:stdio -serial null -nographic \
    -drive if=pflash,format=qcow2,file=$DEPLOY/ovmf.code.qcow2,readonly=on \
    -drive if=pflash,format=qcow2,file=/tmp/ovmf-vars.qcow2

The WIC image and OVMF vars are copied so the originals stay untouched. The
OVMF CODE file is used read-only; the VARS copy is writable so NVRAM (BootNext,
BootOrder, the Mender boot entries) persists across reboots.

Design decisions
================

SATA/AHCI storage (not virtio): virtio devices are not re-enumerated by OVMF
after a guest reboot in QEMU, breaking the boot chain. The kernel fragment
builds AHCI in (no initramfs).

One-shot BootNext for trials: relying on the firmware's own deletion of BootNext
gives true power-loss/boot-failure rollback without a separate bootcount.

CPU model: the wrynose qemux86-64 userspace is built for a CPU baseline that
includes instructions (e.g. AVX2) absent on older emulated models, so QEMU must
present a recent CPU. -cpu IvyBridge panics init with SIGILL; -cpu Skylake-Client
works (the TCG "doesn't support requested feature" warnings it prints are benign).

Fixed rootfs PARTUUIDs: required so the builtin kernel command line can name
rootA for the first boot and the firmware fallback path. Keep CONFIG_CMDLINE in
recipes-kernel/linux/files/efibootmgr-stub.cfg in sync with EFIBOOTMGR_ROOTA_UUID.

Mender state on /data: this layer disables the mender-image feature, which is
what normally relocates /var/lib/mender onto the persistent data partition.
Without that the Mender state DB and agent key live on the rootfs and are
replaced by an A/B update, so the post-reboot ArtifactCommit cannot resume and
the deployment stays stuck at "rebooting". The mender-data-persist recipe
(in meta-mender-demos-common) seeds /data/mender from the build-time
/var/lib/mender on first boot and bind-mounts it over /var/lib/mender,
so the state survives the slot switch and the OTA commits cleanly.

Verifying an update
===================

Build a second artifact and deploy it via hosted.mender.io (the device-type
must match MENDER_DEVICE_TYPE, here qemux86-64-efibootmgr):

  ./make-artifact.sh $DEPLOY/mender-efibootmgr-image-qemux86-64-efibootmgr.ext4 \
      efibootmgr-demo-v2 /tmp/efibootmgr-demo-v2.mender qemux86-64-efibootmgr

On the device the Update Module streams the payload onto the inactive slot
during Download and sets BootNext in ArtifactInstall; mender reboots into the
trial slot, ArtifactVerifyReboot confirms it, and ArtifactCommit moves BootOrder
to that slot. `efibootmgr -v` then shows BootNext gone and BootOrder beginning
with the new slot's entry.

Verified end-to-end on qemux86-64 against hosted.mender.io: first boot on rootA
via the firmware fallback (BootOrder slot A first); an efibootmgr-rootfs OTA
streams to rootB, trial-boots it (BootCurrent = "Mender slot B"), commits
(BootOrder slot B first), and the server reports Success with the device
reporting the new artifact_name. Both rollback paths were confirmed too: a trial
boot that is power-cycled before commit returns to the committed slot (the
firmware has already consumed the one-shot BootNext); and a deliberately broken
artifact whose trial kernel will not boot falls back to the committed slot,
where ArtifactVerifyReboot detects the slot mismatch, ArtifactRollback restores
BootOrder, and the server reports Failure with the device still on the committed
slot and its original artifact_name.
