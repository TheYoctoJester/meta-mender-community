SUMMARY = "Mender update module for Raspberry Pi tryboot A/B rootfs updates"
DESCRIPTION = "Custom Mender update module that handles full system updates \
using the Raspberry Pi native tryboot A/B boot switching mechanism."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://rpi-tryboot-rootfs"

S = "${UNPACKDIR}"

inherit allarch

RDEPENDS:${PN} = "util-linux coreutils sed"

# v3 update modules live here for mender-update 5.x (same across the demos).
MENDER_MODULES_DIR = "${datadir}/mender/modules/v3"

do_install() {
    install -d "${D}${MENDER_MODULES_DIR}"
    install -m 0755 ${UNPACKDIR}/rpi-tryboot-rootfs "${D}${MENDER_MODULES_DIR}/rpi-tryboot-rootfs"
}

FILES:${PN} = "${MENDER_MODULES_DIR}/rpi-tryboot-rootfs"
