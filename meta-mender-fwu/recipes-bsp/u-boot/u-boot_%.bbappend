FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Inject:
#   - the FWU CONFIG fragment (fwu.cfg): enables FWU Multi Bank
#     Update in the U-Boot binary built for qemuarm64-secureboot.
#   - env-nowhere.cfg: switches U-Boot env from MMC (qemu_arm64_
#     defconfig default) to NOWHERE; qemu virt has no MMC, so the
#     stock build would loop on "MMC Device 0 not found". FWU
#     metadata lives in its own GPT partition, so we don't need
#     persistent U-Boot env.
#   - source patches that make the FWU MDATA driver and capsule
#     update path work on QEMU's virtio-blk disk:
#       0001: gpt_blk falls back to scanning UCLASS_BLK for FWU
#             MDATA partitions when no fwu-mdata-store phandle is
#             present.
#       0002: qemu-arm board binds the FWU MDATA driver
#             programmatically from board_late_init() so the driver
#             actually gets probed.
#       0003: qemu-arm registers FWU image types in fw_images[] so
#             FMP matches our capsule UUIDs and routes them to the
#             FWU agent.
#       0004: adds a virtio DFU backend (drivers/dfu/dfu_virtio.c)
#             so capsule payloads can be written to virtio-blk;
#             upstream only ships mmc/scsi/mtd backends.
#       0005: qemu-arm sets update_info.dfu_string with virtio
#             entries for the four FWU partitions, and overrides
#             the weak fwu_plat_get_alt_num() (which hardcodes
#             DFU_DEV_MMC) to match DFU_DEV_VIRTIO entries.
#       0006: qemu-arm's set_dfu_alt_info prefers update_info.dfu
#             _string when set, falling back to the legacy MTD scan
#             otherwise. Without this our virtio entries get
#             overwritten by the default "mtd nor0=u-boot part 1"
#             string.

SRC_URI:append = " \
    file://fwu.cfg \
    file://env-nowhere.cfg \
    file://0001-fwu-mdata-gpt_blk-auto-discover-block-device-on-plat.patch \
    file://0002-board-qemu-arm-bind-FWU-MDATA-driver-without-DT.patch \
    file://0003-board-qemu-arm-register-FWU-image-types-with-FMP.patch \
    file://0004-dfu-add-virtio-backend.patch \
    file://0005-board-qemu-arm-FWU-dfu_string-and-virtio-alt_num.patch \
    file://0006-board-qemu-respect-update_info-dfu_string.patch \
    "
