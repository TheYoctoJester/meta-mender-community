SUMMARY = "Persist Mender state on the /data partition across A/B slot swaps"
DESCRIPTION = "Ships a mender-swupdate-data-seed.service that seeds /data/mender \
from the build-time /var/lib/mender on first boot, plus a var-lib-mender.mount \
unit that bind-mounts /data/mender over /var/lib/mender before the Mender \
services start. Together they keep the Mender state DB and agent key on the \
persistent /data partition (vda4) so the device identity and in-progress \
deployment survive the SWUpdate A/B rootfs swap -- otherwise the server never \
sees the post-reboot commit and the deployment hangs in 'rebooting'."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://mender-swupdate-data-seed.service \
    file://var-lib-mender.mount \
    file://mender-state-debug.service \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
# The seed service must run before var-lib-mender.mount (it populates the
# mount's source), so it is listed first. mender-state-debug is a temporary
# OTA bring-up aid that logs the mount + store state on each boot.
SYSTEMD_SERVICE:${PN} = "mender-swupdate-data-seed.service var-lib-mender.mount mender-state-debug.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/mender-swupdate-data-seed.service \
        ${D}${systemd_system_unitdir}/mender-swupdate-data-seed.service
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
    install -m 0644 ${UNPACKDIR}/mender-state-debug.service \
        ${D}${systemd_system_unitdir}/mender-state-debug.service
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/mender-swupdate-data-seed.service \
    ${systemd_system_unitdir}/var-lib-mender.mount \
    ${systemd_system_unitdir}/mender-state-debug.service \
"
