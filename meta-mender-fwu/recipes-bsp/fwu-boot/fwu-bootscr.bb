SUMMARY = "U-Boot boot script that reads FWU metadata and boots the active bank"
DESCRIPTION = "Compiles boot.cmd into boot.scr.uimg via mkimage and deploys \
it to DEPLOY_DIR_IMAGE. The script is then placed in the ESP by wic so \
U-Boot's distroboot picks it up."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://boot.cmd"

DEPENDS = "u-boot-tools-native"

inherit deploy

do_compile() {
    mkimage -A arm64 -O linux -T script -C none \
            -n "FWU-aware boot script for qemuarm64-secureboot" \
            -d ${UNPACKDIR}/boot.cmd ${B}/boot.scr.uimg
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/boot.scr.uimg ${DEPLOYDIR}/boot.scr.uimg
}

addtask deploy after do_compile before do_build
