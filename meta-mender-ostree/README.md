# meta-mender-ostree

**Status: verified end-to-end** (full OTA round-trip on hosted.mender.io, CI run
#2443: apply-offline → `admin deploy` → reboot into v2 → commit, server reports
success). Mender OTA on top of an
[OSTree](https://ostreedev.github.io/ostree/)-managed root filesystem, on Yocto
wrynose, qemuarm64 + U-Boot. This is a "Family B" demo: OSTree is the on-device
atomic-update engine, the Mender client runs in **client-only** mode
(`meta-mender-client-only`), and a custom `ostree` Update Module applies an
OSTree static delta carried inside a Mender artifact — Mender is the
deployment/management plane, OSTree does the atomic switch.

## Why a dedicated layer

OSTree is not an A/B-partition scheme like the RAUC/SWUpdate demos: there is a
single rootfs holding an OSTree sysroot (`/ostree/repo` + deployments), the
bootloader selects a deployment via Boot Loader Spec entries (`ostree=` kernel
arg), and `/var` is shared/persistent across deployments (so `/var/lib/mender`
— the agent key + state DB — survives a deployment switch with no bind-mount).

The OSTree-ification (read-only `/usr`, `/etc` 3-way merge, `/var` split,
`ostree_repo`, deployment layout) comes from
[meta-updater](https://github.com/uptane/meta-updater)'s `sota` /
`image_types_ostree`. The Uptane/aktualizr client is stripped out — the
management plane here is Mender, not Uptane. meta-updater ships no
`sota_qemuarm64`, so this layer provides the qemuarm64 + U-Boot machine glue.

## What this layer provides

* `conf/machine/qemuarm64-ostree.conf` — qemuarm64 + U-Boot, `OSTREE_BOOTLOADER
  = "u-boot"`, boot via `u-boot.bin` under runqemu.
* `files/wic/qemuarm64-ostree.wks` — FAT `/boot` + the OSTree physical sysroot
  (`--source otaimage`) as root.
* `recipes-core/images/mender-ostree-image.bb` — the demo rootfs (OSTree +
  Mender client-only). Sets `IMAGE_ROOTFS_EXTRA_SPACE` so the deployed ext4 has
  headroom for the second deployment + the delta apply (otherwise OSTree's
  `min-free-space-percent` guard rejects `apply-offline`), and stashes the
  factory `/var/lib/mender` into `/usr/lib/mender-factory` for first-boot seed.
* `recipes-core/images/all-images.bb` — build handle (image + the v2 delta).
* `recipes-extended/mender-update-module-ostree/` — the `ostree` Update Module
  (`static-delta apply-offline` → `admin deploy` → reboot → verify → commit →
  rollback).
* `recipes-extended/ostree-update-bundle/` — build-time **v2 static-delta**
  payload: commit a changed v2, then
  `ostree static-delta generate --min-fallback-size=0 --inline` (`--inline` is
  essential — it embeds the delta parts into a single self-contained file, so
  the Mender artifact ships everything `apply-offline` needs).
* `recipes-mender/mender-ostree-data/` — first-boot seed of the factory
  `/var/lib/mender` (device_type etc.) into the persistent `/var`, which OSTree
  starts empty.

## Consumed by

The kas wrapper `yocto/wrynose/floating/qemuarm64-ostree.yml` on branch
`wrynose-demos` of `theyoctojester/mender-community-images`, and the
`build-yocto-wrynose-demo.yml` CI (Capability C, `ota_kind = ostree`).

## Runtime quirks discovered during bring-up

1. **U-Boot OSTree boot on qemuarm64.** meta-updater ships no `sota_qemuarm64`
   nor a U-Boot OTA boot script; the machine glue + `boot.cmd` are authored here.
   The rootfs must be selected with `root=` (the initramfs-framework `rootfs`
   module mounts it, then the `ostree` module runs `ostree-prepare-root`), not
   meta-updater's `ostree_root=`.
2. **`/var` starts empty.** OSTree wipes `/var` of deployment content, so
   `/var/lib/mender/device_type` installed by the client recipes is gone at
   runtime. `mender-ostree-data` stashes it to `/usr/lib/mender-factory` at build
   and a first-boot service seeds it into the persistent `/var`.
3. **Self-contained static delta.** `static-delta generate` without `--inline`
   writes the superblock plus *separate* deltapart files; shipping only the
   superblock makes on-device `apply-offline` fail with "Opening deltapart '0':
   No such file or directory". `--inline` produces one self-contained file.
4. **Rootfs free space.** The `otaimage` ext4 ships nearly full; the second
   (v2) deployment + `/var` writes leave it at the 3% mark, so `apply-offline`
   trips OSTree's `min-free-space-percent` guard. `IMAGE_ROOTFS_EXTRA_SPACE`
   gives the needed headroom.
5. **(CI, not this layer) distinct QEMU slirp MAC per demo.** All slirp demos
   otherwise share `52:54:00:12:35:02` and collide on one Mender device identity
   when they run concurrently — see the per-demo `QB_NETWORK_DEVICE:forcevariable`
   in the kas wrappers.
