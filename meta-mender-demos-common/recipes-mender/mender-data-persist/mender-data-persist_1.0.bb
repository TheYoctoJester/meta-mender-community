SUMMARY = "Persist Mender state on the /data partition across A/B rootfs swaps"
DESCRIPTION = "Ships a systemd-tmpfiles snippet that seeds /data/mender from the \
build-time /var/lib/mender on first boot, plus a var-lib-mender.mount unit that \
bind-mounts /data/mender over /var/lib/mender before the Mender services start. \
Demos that disable the mender-image feature lose meta-mender's normal relocation \
of Mender state onto the data partition; without it the state DB and agent key \
live on the rootfs and are replaced by an A/B update, so the post-reboot \
ArtifactCommit cannot resume and the deployment never leaves 'rebooting'. \
Keeping the state on the persistent /data partition lets it survive the swap. \
Shared by the bootloader-rollback demos (efibootmgr, x86 U-Boot EFI, ...) that \
previously each carried an identical mender-*-data recipe."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-data-persist.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"

do_install() {
    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-data-persist.conf \
        ${D}${libdir}/tmpfiles.d/mender-data-persist.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
}

FILES:${PN} += " \
    ${libdir}/tmpfiles.d/mender-data-persist.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
"
