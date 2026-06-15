SUMMARY = "Mender Update Module + first-boot provisioning for UEFI A/B switching"
DESCRIPTION = "Ships 'efibootmgr-rootfs', a Mender Update Module that performs \
A/B rootfs updates by writing the inactive slot, copying its EFI-stub kernel \
onto the ESP, and switching the UEFI boot manager (BootNext for the trial \
boot, BootOrder on commit). Also ships a one-shot first-boot service that \
registers the two per-slot UEFI boot entries via efibootmgr."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://efibootmgr-rootfs \
    file://mender-efibootmgr-bootentry.sh \
    file://mender-efibootmgr-bootentry.service \
"

S = "${UNPACKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "mender-efibootmgr-bootentry.service"

RDEPENDS:${PN} = " \
    bash \
    efibootmgr \
    util-linux \
    util-linux-blkid \
    util-linux-findmnt \
    coreutils \
"

do_install() {
    install -d ${D}/usr/share/mender/modules/v3
    install -m 0755 ${UNPACKDIR}/efibootmgr-rootfs \
        ${D}/usr/share/mender/modules/v3/efibootmgr-rootfs

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/mender-efibootmgr-bootentry.sh \
        ${D}${bindir}/mender-efibootmgr-bootentry.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/mender-efibootmgr-bootentry.service \
        ${D}${systemd_system_unitdir}/mender-efibootmgr-bootentry.service
}

FILES:${PN} = " \
    /usr/share/mender/modules/v3/efibootmgr-rootfs \
    ${bindir}/mender-efibootmgr-bootentry.sh \
    ${systemd_system_unitdir}/mender-efibootmgr-bootentry.service \
"
