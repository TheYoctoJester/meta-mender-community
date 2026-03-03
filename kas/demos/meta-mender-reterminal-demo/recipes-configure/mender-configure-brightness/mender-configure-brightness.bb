SUMMARY = "Mender Configure apply script for display brightness"
DESCRIPTION = "Applies display brightness settings from Mender Configure."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://brightness"

RDEPENDS:${PN} = "mender-configure jq"

do_install() {
    install -d ${D}/usr/lib/mender-configure/apply-device-config.d
    install -m 0755 ${WORKDIR}/brightness ${D}/usr/lib/mender-configure/apply-device-config.d/
}

FILES:${PN} = "/usr/lib/mender-configure/apply-device-config.d/brightness"
