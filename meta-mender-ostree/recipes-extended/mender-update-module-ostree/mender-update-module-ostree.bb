SUMMARY = "Mender Update Module that applies OSTree static deltas"
DESCRIPTION = "Installs the 'ostree' v3 Update Module so the Mender server can \
deploy OSTree updates: a self-contained OSTree static delta (+ target commit) \
wrapped in a Mender artifact of payload type 'ostree' is applied with \
'ostree static-delta apply-offline' and deployed with 'ostree admin deploy'. \
OSTree + the bootloader own the atomic deployment switch and rollback; Mender \
owns delivery, reboot and commit."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://ostree"
S = "${UNPACKDIR}"

inherit allarch

# Runtime: the ostree CLI on the target. mender-update owns the modules dir.
RDEPENDS:${PN} = "ostree"

# v3 update modules live here for mender-update 5.x (same as the other demos).
MENDER_MODULES_DIR = "${datadir}/mender/modules/v3"

do_install() {
    install -d "${D}${MENDER_MODULES_DIR}"
    install -m 0755 "${UNPACKDIR}/ostree" "${D}${MENDER_MODULES_DIR}/ostree"
}

FILES:${PN} = "${MENDER_MODULES_DIR}/ostree"
