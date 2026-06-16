SUMMARY = "fw_setenv/fw_printenv shim for Mender on a UKI + systemd-boot system"
DESCRIPTION = "Drives Mender A/B on a UKI + systemd-boot system via \
systemd-boot's boot counting. On install it stages the inactive slot's UKI \
onto the ESP with a +N tries counter (so systemd-boot trials it and falls \
back automatically if it is never blessed); on commit it strips the counter \
to make the slot permanent. mender_boot_part is answered by introspecting \
the running root (root=PARTLABEL), so systemd-boot is the single source of \
truth for slot selection. Used in place of u-boot-fw-utils when no U-Boot \
env is reachable from userspace (the case on qemuarm64-secureboot, where \
U-Boot is the UEFI runtime and there is no fw_env partition). \
\
Masks systemd-bless-boot.service: the bless (counter strip) is done by this \
shim from the running slot, not by systemd's tooling, which depends on the \
LoaderBootCountPath EFI variable that U-Boot's UEFI runtime does not \
reliably expose to Linux. \
\
Also ships a tmpfiles snippet + a var-lib-mender.mount unit that together \
bind-mount /data/mender over /var/lib/mender before the mender services \
start, so the mender state DB and the agent key live on the persistent \
data partition and survive the rootfs swap of an OTA."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-uki-shim.sh \
    file://mender-uki-data.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

RDEPENDS:${PN} += "systemd"
RCONFLICTS:${PN} = "u-boot-fw-utils libubootenv-bin"
SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"

inherit systemd

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/mender-uki-shim.sh ${D}${bindir}/mender-uki-shim
    ln -sf mender-uki-shim ${D}${bindir}/fw_setenv
    ln -sf mender-uki-shim ${D}${bindir}/fw_printenv

    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-uki-data.conf \
        ${D}${libdir}/tmpfiles.d/mender-uki-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount

    # Mask systemd-bless-boot.service. The bless is done by the shim (direct
    # counter-strip rename from the running slot); systemd's own bless relies
    # on the LoaderBootCountPath EFI variable that U-Boot's UEFI runtime does
    # not reliably expose, and could otherwise either fail or race the shim.
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-bless-boot.service
}

FILES:${PN} += " \
    ${bindir}/mender-uki-shim \
    ${bindir}/fw_setenv \
    ${bindir}/fw_printenv \
    ${libdir}/tmpfiles.d/mender-uki-data.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
    ${sysconfdir}/systemd/system/systemd-bless-boot.service \
"
