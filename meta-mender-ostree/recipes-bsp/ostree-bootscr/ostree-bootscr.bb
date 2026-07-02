SUMMARY = "U-Boot boot script that boots the active OSTree deployment (qemuarm64)"
DESCRIPTION = "Compiles boot.cmd into boot.scr.uimg via mkimage and deploys it \
to DEPLOY_DIR_IMAGE. IMAGE_BOOT_FILES places it on the FAT boot partition, \
where U-Boot's distroboot scan runs it. The script imports OSTree's \
/boot/loader/uEnv.txt from the sysroot and boots the referenced deployment \
kernel + initramfs with the ostree= bootargs. meta-updater ships no \
u-boot-otascript for qemuarm64, so this provides that role."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://boot.cmd"

DEPENDS = "u-boot-tools-native"

inherit deploy

do_compile() {
    mkimage -A arm64 -O linux -T script -C none \
            -n "OSTree boot script for qemuarm64" \
            -d ${UNPACKDIR}/boot.cmd ${B}/boot.scr.uimg
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/boot.scr.uimg ${DEPLOYDIR}/boot.scr.uimg
}

addtask deploy after do_compile before do_build
