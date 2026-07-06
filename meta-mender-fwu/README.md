# meta-mender-fwu

**Status: verified end-to-end** (Mender OTA on hosted.mender.io, run #2450).

Mender OTA on top of [U-Boot's FWU Multi Bank
Update](https://docs.u-boot.org/en/latest/develop/uefi/fwu_updates.html)
on Yocto wrynose. End-to-end verified against hosted.mender.io on
`qemuarm64-secureboot` from meta-arm: deploy a `rootfs-image-fwu`
artifact, U-Boot's capsule-on-disk scanner applies it on the next boot,
the active bank flips, ArtifactCommit accepts the new bank via the FWU
metadata, and the server reports Success.

## Why a dedicated layer

Mender's stock A/B flow on U-Boot uses `fw_setenv` against persistent
U-Boot env (via the `mender-uboot` MENDER_FEATURE). FWU Multi Bank
Update is a different substrate: U-Boot itself owns the active/previous
bank selection through a versioned metadata structure on two dedicated
GPT partitions, and the actual rootfs swap is driven by U-Boot's EFI
Firmware Management Protocol over a capsule the userspace drops into the
ESP. There is no `fw_setenv` to wire to.

`meta-mender-fwu` replaces the bank-selection substrate without touching
meta-mender:

  * `mender-uboot` MENDER_FEATURE is disabled.
  * `mender-image` / `mender-update-install` / `mender-systemd` are
    enabled, so meta-mender ships the canonical client + systemd units
    and lays out `/var/lib/mender` as a symlink to `/data/mender`.
  * A custom `rootfs-image-fwu` Update Module drives the bank flip via
    `mkeficapsule` + the U-Boot FWU agent.

## What this layer provides

* `recipes-bsp/u-boot/` — six patches against U-Boot 2026.01:
    1. `gpt_blk` falls back to scanning UCLASS_BLK for FWU metadata
       partitions when no `fwu-mdata-store` DT phandle is present (qemu
       virt has no FDT entry for this).
    2. qemu-arm board binds the FWU MDATA driver programmatically from
       `board_late_init()` so the driver gets probed.
    3. qemu-arm registers FWU image types in `fw_images[]` so the FMP
       routes capsule UUIDs to the FWU agent.
    4. Adds a virtio DFU backend (`drivers/dfu/dfu_virtio.c`) — upstream
       only ships mmc/scsi/mtd backends, but qemu-arm's storage is
       virtio-blk.
    5. qemu-arm publishes `update_info.dfu_string` with the four FWU
       partitions and overrides the weak `fwu_plat_get_alt_num()`
       (hardcoded `DFU_DEV_MMC`) for `DFU_DEV_VIRTIO`.
    6. qemu's `set_dfu_alt_info` respects `update_info.dfu_string` when
       set rather than overwriting it with the MTD scan default.

  Plus two Kconfig fragments: `fwu.cfg` enables `FWU_MULTI_BANK_UPDATE`
  + `EFI_CAPSULE_ON_DISK_EARLY` + the virtio DFU backend;
  `env-nowhere.cfg` switches the U-Boot env to `NOWHERE` (qemu virt has
  no MMC for the default env store).

* `recipes-bsp/fwu-boot/` — `boot.cmd` compiled to a `boot.scr.uimg`
  that distroboot picks up from the ESP. The script reads the active
  bank index from FWU metadata, loads the kernel from the active bank's
  GPT partition, hands off to `bootefi` with the qemu-supplied FDT, and
  provisions an EFI BootOrder entry so capsule-on-disk has a stable
  bootflow to walk on subsequent boots.

* `recipes-bsp/fwu-mdata/` — generates the initial FWU v1 metadata
  binary that wic stages into the two metadata partitions. Bank 0 starts
  active + accepted; bank 1 starts unaccepted. Two images per bank
  (kernel + rootfs).

* `recipes-support/libfwumdata/` — packages
  [passgat/libfwumdata](https://github.com/passgat/libfwumdata) +
  `yafwumdata` so the Update Module can flip bank state from userspace.
  A one-patch fix extends `yafwumdata -s` to also set the per-image
  acceptance byte on FWU V1 (V2 already worked).

* `recipes-support/fwumdata-config/` — installs `/etc/fwumdata.config`
  pointing `yafwumdata`/`libfwumdata` at the FWU metadata GPT partitions.

* `recipes-extended/mender-update-module-fwu/` — ships
  `rootfs-image-fwu` (Update Module type). Hooks:
    * `NeedsArtifactReboot` returns `Automatic`.
    * `ArtifactInstall` copies the capsule from the artifact payload to
      `/boot/efi/EFI/UpdateCapsule/`.
    * `ArtifactVerifyReboot` confirms the running rootfs partition
      matches the bank that FWU now reports as active.
    * `ArtifactCommit` calls `yafwumdata -s "<active>" accepted` to mark
      the new bank accepted in FWU metadata.
    * `ArtifactRollback` flips the active index back via `yafwumdata`.

* `recipes-core/images/core-image-fwu-test.bb` — minimal demo image
  that pulls in the tooling needed to interact with FWU metadata and
  capsules from userspace (`u-boot-tools`, `efivar`, `efibootmgr`,
  `libfwumdata`, `parted`, etc.).

* `files/wic/qemuarm64-fwu.wks.in` — 8-partition GPT:

    | # | role          | type | size  | label              |
    |---|---------------|------|-------|--------------------|
    | 1 | ESP           | FAT  | 1024M | esp                |
    | 2 | FWU mdata pri | raw  |   64K | fwu-mdata-pri      |
    | 3 | FWU mdata sec | raw  |   64K | fwu-mdata-sec      |
    | 4 | bank0 kernel  | raw  |   32M | bank0-kernel       |
    | 5 | bank0 rootfs  | ext4 |  512M | bank0-rootfs       |
    | 6 | bank1 kernel  | raw  |   32M | bank1-kernel       |
    | 7 | bank1 rootfs  | ext4 |  512M | bank1-rootfs       |
    | 8 | data          | ext4 | 1536M | data               |

  The wic file pre-populates `/data` from the rootfs's `/data/` tree at
  image-construction time, so `/data/mender/device_type` arrives
  pre-seeded and the mender client picks it up via the `/var/lib/mender
  → /data/mender` symlink that meta-mender's `mender-image` MENDER_FEATURE
  configures.

## Four runtime quirks worth knowing

Each cost a build/deploy cycle to discover.

1. **EFI BootOrder must be provisioned.** U-Boot's capsule-on-disk
   scanner walks the EFI BootOrder list to find the ESP at the top of
   boot. Stock qemuarm64-secureboot has no `BootOrder` set and the
   variable store survives reboots, so the scan silently does nothing on
   subsequent boots. `boot.cmd` therefore calls `efidebug boot add` +
   `efidebug boot order 0001` on every boot — idempotent, and the
   resulting boot entry's PE-COFF load failure is benign (U-Boot falls
   back to the bootflow scan immediately).

2. **FWU V1 per-image acceptance.** U-Boot's FWU V1 metadata format
   tracks `accepted` as one byte per `(bank, image)` pair. `yafwumdata
   -s <bank> accepted` originally rejected V1 outright (V2 layout
   only); the patch in `recipes-support/libfwumdata/files/` flips the
   per-image bytes, which is what `bank N state set to accepted (0xfc)`
   actually means.

3. **`/var/lib/mender` must be on the data partition.** Mender's
   keypair + state DB live there; an FWU bank swap replaces the rootfs
   wholesale, so without persistence the post-reboot mender client has
   no record of the deployment and the server reports Failure. The
   `mender-image` MENDER_FEATURE in meta-mender already lays out
   `/var/lib/mender → /data/mender`; pointing
   `MENDER_DATA_PART="/dev/disk/by-partlabel/data"` at the persistent
   GPT partition is what makes the bind survive.

4. **U-Boot 2026.01 ships `mkeficapsule` natively.** Earlier scarthgap
   integrations needed a bbappend to add it back after meta-lts-mixins
   dropped it. On wrynose that bbappend would double-register the
   package and break `do_package`. Don't add one here.

## Reproducing the build

This layer is consumed by the matching kas wrapper at
`yocto/wrynose/floating/qemuarm64-fwu.yml` on branch `wrynose-demos` of
`theyoctojester/mender-community-images`:

```sh
git clone https://github.com/theyoctojester/mender-community-images.git
cd mender-community-images
git checkout wrynose-demos
kas build yocto/wrynose/floating/qemuarm64-fwu.yml
```

The kas wrapper pins the meta-mender-community fork at this branch and
inherits the rest of the wrynose stack (openembedded-core, meta-yocto,
meta-openembedded, meta-arm, meta-mender) from
`include/mender-base.yml` and `include/arm.yml`.

## Boot chain

```
QEMU
  -> trusted-firmware-a (flash.bin from meta-arm)
  -> U-Boot 2026.01 (with this layer's patches + fwu.cfg)
  -> distroboot reads boot.scr.uimg from the ESP
  -> boot.cmd reads FWU metadata, picks the active bank
  -> bootefi loads kernel from bank N's kernel partition (with qemu's FDT)
  -> kernel root=/dev/disk/by-partlabel/bank<N>-rootfs
```

Capsule-on-disk runs *before* `boot.cmd`: at U-Boot startup, if
`/boot/efi/EFI/UpdateCapsule/` contains a capsule whose `image_type_guid`
is registered in `fw_images[]`, the FWU agent writes it to the inactive
bank's partition (resolved via `update_info.dfu_string` →
`fwu_plat_get_alt_num` → the matching DFU virtio alt entry) and flips
`active_index` in the metadata. The capsule file is then deleted. On
the next reboot, `boot.cmd` reads the new `active_index` and loads from
the freshly-written bank.

## Verification recipe

After `kas build` completes:

```sh
kas shell yocto/wrynose/floating/qemuarm64-fwu.yml \
    -c "runqemu qemuarm64-secureboot nographic serial wic slirp"
```

Inside the guest, the following should all hold on a fresh boot:

```sh
mount | grep ' / '                        # /dev/vda5  (bank 0 rootfs)
mount | grep /data                        # /dev/vda8 -> /data
ls -l /var/lib/mender                     # symlink -> /data/mender
yafwumdata -B 2 -I 2 -s show              # Active Index: 0
mender-update show-provides               # artifact_name=fwu-wrynose-v1
```

After deploying a `rootfs-image-fwu` artifact built via this layer's
demo tooling, the next boot lands on bank 1:

```sh
findmnt / -o SOURCE -n                    # /dev/vda7  (bank 1 rootfs)
yafwumdata -B 2 -I 2 -s show              # Active Index: 1
journalctl -u mender-updated | grep accepted
# "bank 1 state set to accepted (0xfc)"
```

The OTA artifact is built by `make-artifact.sh` at the layer root, which
wraps the demo rootfs into an FMP capsule (`mkeficapsule`) and packs it
into a `rootfs-image-fwu` Mender Artifact:

```sh
kas shell yocto/wrynose/floating/qemuarm64-fwu.yml -c '
  meta-mender-community/meta-mender-fwu/make-artifact.sh \
    build/tmp/deploy/images/qemuarm64-secureboot/core-image-fwu-test-qemuarm64-secureboot.rootfs.ext4 \
    fwu-wrynose-v2 \
    /tmp/fwu-wrynose-v2.mender'
```

Deploy `/tmp/fwu-wrynose-v2.mender` to the device on hosted.mender.io
(upload artifact, accept device, deploy, observe bank flip, server
reports Success). The `build-yocto-wrynose-demo.yml` workflow in
`mender-integration-builds` drives exactly this round-trip in CI under
`runqemu` (Capability C).

## License

`meta-mender-fwu/LICENSE` (Apache-2.0). Individual recipes specify their
own `LICENSE` per Yocto convention.
