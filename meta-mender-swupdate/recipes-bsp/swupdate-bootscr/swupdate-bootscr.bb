SUMMARY = "U-Boot boot script that selects the active A/B rootfs slot via 'rootpart'"
DESCRIPTION = "Compiles boot.cmd into boot.scr.uimg via mkimage and deploys \
it to DEPLOY_DIR_IMAGE. IMAGE_BOOT_FILES then places it in the FAT boot \
partition, where U-Boot's distroboot scan picks it up. The script reads the \
'rootpart' env variable (set by SWUpdate's bootloader handler) and boots \
the matching /dev/vda partition."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://boot.cmd"

DEPENDS = "u-boot-tools-native"

inherit deploy

do_compile() {
    mkimage -A arm64 -O linux -T script -C none \
            -n "SWUpdate A/B boot script for qemuarm64" \
            -d ${UNPACKDIR}/boot.cmd ${B}/boot.scr.uimg
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/boot.scr.uimg ${DEPLOYDIR}/boot.scr.uimg
}

addtask deploy after do_compile before do_build
