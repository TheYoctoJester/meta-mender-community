SUMMARY = "Persist Mender state on the RAUC /data partition"
DESCRIPTION = "Ships a mender-rauc-data-seed.service that seeds /data/mender \
from the build-time /var/lib/mender on first boot, plus a var-lib-mender.mount \
unit that bind-mounts /data/mender over /var/lib/mender before the Mender \
services start. Together they keep the Mender state DB and agent key on RAUC's \
persistent /data partition so the device identity and in-progress deployment \
survive an A/B slot swap (otherwise the server reports Failure on the \
post-reboot commit)."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-rauc-data-seed.service \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
# The seed service must be ordered before var-lib-mender.mount (it sets up the
# mount's source), so enable it first.
SYSTEMD_SERVICE:${PN} = "mender-rauc-data-seed.service var-lib-mender.mount"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/mender-rauc-data-seed.service \
        ${D}${systemd_system_unitdir}/mender-rauc-data-seed.service
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/mender-rauc-data-seed.service \
    ${systemd_system_unitdir}/var-lib-mender.mount \
"
