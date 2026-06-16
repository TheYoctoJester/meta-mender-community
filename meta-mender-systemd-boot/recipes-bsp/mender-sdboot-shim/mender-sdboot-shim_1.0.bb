SUMMARY = "fw_setenv/fw_printenv shim for Mender on a systemd-boot system"
DESCRIPTION = "Maps Mender's A/B boot environment onto stock systemd-boot's \
on-ESP state, using systemd's native Automatic Boot Assessment for rollback. \
On a slot flip it refreshes the target slot's kernel/initrd on the ESP from \
that slot's rootfs, writes the slot's Type #1 boot entry with a boot counter \
in its filename (arming a one-shot trial) and points loader.conf `default` at \
it; on commit it strips the counter so the slot becomes a permanent good \
entry. A trial that panics or is power-cycled before commit counts out, and \
the firmware boots the still-good committed slot -- rollback without patching \
systemd-boot. \
\
Also ships a tmpfiles snippet + a var-lib-mender.mount unit that bind-mount \
/data/mender over /var/lib/mender before the mender services start, so the \
Mender state DB and agent key survive the rootfs swap of an OTA; and masks \
systemd's automatic systemd-bless-boot.service so only Mender's commit \
blesses a trial boot."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://mender-sdboot-shim.sh \
    file://mender-sdboot-data.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

# Build-time knobs, kept in sync with mender-systemd-boot-ab.bbclass. Set
# globally (kas wrapper) so the image class and this recipe agree.
MENDER_SDBOOT_BOOT_TRIES ?= "1"
MENDER_SDBOOT_APPEND ?= "rootwait rw console=ttyS0,115200 panic=5 systemd.gpt_auto=0"

# findmnt/mount/readlink + blockdev (flush stale buffers before reading the
# just-written inactive slot) for the kernel refresh; systemd for the units.
RDEPENDS:${PN} += "util-linux-findmnt util-linux-mount util-linux-blockdev systemd"
RCONFLICTS:${PN} = "u-boot-fw-utils libubootenv-bin"
SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"

inherit systemd

do_install() {
    install -d ${D}${bindir}
    sed -e 's|@TRIES@|${MENDER_SDBOOT_BOOT_TRIES}|g' \
        -e 's|@APPEND@|${MENDER_SDBOOT_APPEND}|g' \
        ${UNPACKDIR}/mender-sdboot-shim.sh > ${D}${bindir}/mender-sdboot-shim
    chmod 0755 ${D}${bindir}/mender-sdboot-shim
    ln -sf mender-sdboot-shim ${D}${bindir}/fw_setenv
    ln -sf mender-sdboot-shim ${D}${bindir}/fw_printenv

    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-sdboot-data.conf \
        ${D}${libdir}/tmpfiles.d/mender-sdboot-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount

    # Mask systemd's automatic boot-assessment blessing so a trial slot is
    # only ever blessed by Mender's ArtifactCommit (via the shim). Without
    # this, boot-complete.target would mark the trial "good" on first
    # successful boot, defeating Mender-controlled rollback.
    install -d ${D}${sysconfdir}/systemd/system
    ln -sf /dev/null ${D}${sysconfdir}/systemd/system/systemd-bless-boot.service
}

FILES:${PN} += " \
    ${bindir}/mender-sdboot-shim \
    ${bindir}/fw_setenv \
    ${bindir}/fw_printenv \
    ${libdir}/tmpfiles.d/mender-sdboot-data.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
    ${sysconfdir}/systemd/system/systemd-bless-boot.service \
"
