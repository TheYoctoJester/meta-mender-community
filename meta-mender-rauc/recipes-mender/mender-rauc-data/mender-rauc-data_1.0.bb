SUMMARY = "Persist Mender state on the RAUC /data partition"
DESCRIPTION = "Ships a tmpfiles snippet that seeds /data/mender from the \
build-time /var/lib/mender on first boot, plus a var-lib-mender.mount unit that \
bind-mounts /data/mender over /var/lib/mender before the Mender services start. \
Together they keep the Mender state DB and agent key on RAUC's persistent /data \
partition so the device identity and in-progress deployment survive an A/B slot \
swap (otherwise the server reports Failure on the post-reboot commit)."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-rauc-data.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"

do_install() {
    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-rauc-data.conf \
        ${D}${libdir}/tmpfiles.d/mender-rauc-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
}

FILES:${PN} += " \
    ${libdir}/tmpfiles.d/mender-rauc-data.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
"
