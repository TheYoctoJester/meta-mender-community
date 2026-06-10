SUMMARY = "Mender Update Module that installs RAUC bundles"
DESCRIPTION = "Installs the 'rauc' v3 Update Module so the Mender server can \
deploy RAUC bundles: a signed .raucb wrapped in a Mender artifact of payload \
type 'rauc' is handed to RAUC via 'rauc install'. RAUC + the bootloader own the \
A/B slot switch and rollback; Mender owns delivery, reboot and commit."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://rauc"

S = "${UNPACKDIR}"

inherit allarch

# Runtime: RAUC on the target. The mender client (mender-update) owns the
# /usr/share/mender/modules/v3 directory at runtime.
RDEPENDS:${PN} = "rauc"

# v3 update modules live here for mender-update 5.x.
MENDER_MODULES_DIR = "${datadir}/mender/modules/v3"

do_install() {
    install -d "${D}${MENDER_MODULES_DIR}"
    install -m 0755 "${UNPACKDIR}/rauc" "${D}${MENDER_MODULES_DIR}/rauc"
}

FILES:${PN} = "${MENDER_MODULES_DIR}/rauc"
