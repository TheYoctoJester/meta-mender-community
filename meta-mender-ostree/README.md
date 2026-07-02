# meta-mender-ostree

**Status: work in progress (bring-up).** Mender OTA on top of an
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
  Mender client-only).
* `recipes-core/images/all-images.bb` — build handle (image, plus the v2 delta
  once added).
* _(planned)_ `recipes-mender/mender-update-module-ostree/` — the `ostree`
  Update Module (`static-delta apply-offline` → `admin deploy` → reboot →
  verify → commit → rollback).
* _(planned)_ build-time **v2 static-delta** payload (commit a changed v2, then
  `ostree static-delta generate --min-fallback-size=0`).
* _(planned)_ first-boot seed of `device_type` into the persistent
  `/var/lib/mender` if OSTree's `/var` population doesn't carry it.

## Consumed by

The kas wrapper `yocto/wrynose/floating/qemuarm64-ostree.yml` on branch
`wrynose-demos` of `theyoctojester/mender-community-images`, and (once green)
the `build-yocto-wrynose-demo.yml` CI (Capability C, `ota_kind = ostree`).

## Bring-up gates (see the plan)

1. OSTree image builds on the wrynose + meta-updater + meta-arm/mender stack
   (aktualizr stripped; `sota_sanity` GARAGE defaults).
2. U-Boot boots an OSTree deployment on qemuarm64 under runqemu (no
   `sota_qemuarm64` / `u-boot-otascript` upstream — authored here).
3. `device_type` seeding in the OSTree `/var` model.
4. v2 commit + static-delta correctness.
5. Full OTA timing under TCG.
