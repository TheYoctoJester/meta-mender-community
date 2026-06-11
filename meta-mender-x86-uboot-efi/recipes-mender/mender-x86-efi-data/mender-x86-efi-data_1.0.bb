SUMMARY = "Persist Mender state on the /data partition for the x86 U-Boot EFI demo"
DESCRIPTION = "Ships a tmpfiles snippet that seeds /data/mender from the \
build-time /var/lib/mender on first boot, plus a var-lib-mender.mount unit that \
bind-mounts /data/mender over /var/lib/mender before the Mender services start. \
mender-explicit-wic disables the mender-image feature, which is what normally \
relocates Mender state onto the data partition; without that, the state DB and \
agent key live on the rootfs and are replaced by an A/B update, so the \
post-reboot ArtifactCommit cannot resume and the deployment never leaves the \
'rebooting' state. Keeping the state on the persistent /data partition lets it \
survive the slot swap."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-x86-efi-data.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"

do_install() {
    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-x86-efi-data.conf \
        ${D}${libdir}/tmpfiles.d/mender-x86-efi-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
}

FILES:${PN} += " \
    ${libdir}/tmpfiles.d/mender-x86-efi-data.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
"
