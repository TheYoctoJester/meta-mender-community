SUMMARY = "Initial FWU Multi Bank Update v1 metadata image"
DESCRIPTION = "Generates the FWU v1 metadata binary (fwu-mdata.bin) that \
seeds the two FWU metadata partitions in the wic image. Bank 0 starts \
active+accepted, bank 1 starts unaccepted. Matches U-Boot v2024.01 layout."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fwu-mdata-tool"

DEPENDS = "python3-native"

inherit deploy

do_compile() {
    python3 ${UNPACKDIR}/fwu-mdata-tool generate-initial \
        --output ${B}/fwu-mdata.bin \
        --kernel-type-uuid ${FWU_KERNEL_IMAGE_TYPE_UUID} \
        --rootfs-type-uuid ${FWU_ROOTFS_IMAGE_TYPE_UUID} \
        --bank0-kernel-uuid ${FWU_BANK0_KERNEL_IMAGE_UUID} \
        --bank0-rootfs-uuid ${FWU_BANK0_ROOTFS_IMAGE_UUID} \
        --bank1-kernel-uuid ${FWU_BANK1_KERNEL_IMAGE_UUID} \
        --bank1-rootfs-uuid ${FWU_BANK1_ROOTFS_IMAGE_UUID}
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/fwu-mdata.bin ${DEPLOYDIR}/fwu-mdata.bin
}

addtask deploy after do_compile before do_build
