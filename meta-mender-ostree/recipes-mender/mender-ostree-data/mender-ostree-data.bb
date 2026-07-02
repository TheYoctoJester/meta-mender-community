SUMMARY = "First-boot seed of /var/lib/mender for the OSTree demo"
DESCRIPTION = "OSTree keeps /var across deployments but starts it empty of \
deployment content, so the Mender state dir (/var/lib/mender: device_type, \
mender.conf, agent key/state) installed into the rootfs is missing at runtime. \
This ships a systemd service that seeds /var/lib/mender from a factory stash \
(/usr/lib/mender-factory, carried read-only in the OSTree deployment) on first \
boot, before the Mender services start. The image recipe populates the stash \
via ROOTFS_POSTPROCESS_COMMAND."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://mender-ostree-data-seed.service"

inherit systemd
SYSTEMD_SERVICE:${PN} = "mender-ostree-data-seed.service"
# No compiled content; allow an empty main package.
ALLOW_EMPTY:${PN} = "1"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/mender-ostree-data-seed.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${systemd_system_unitdir}/mender-ostree-data-seed.service"
