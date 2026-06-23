SUMMARY = "Persist Mender state on the /var/lib/mender partition across A/B swaps"
DESCRIPTION = "vda4 is mounted directly at /var/lib/mender (see the fstab \
fragment), so the Mender agent key + state DB live on the persistent partition \
and survive the SWUpdate A/B rootfs swap. This recipe ships the first-boot seed \
service that populates the (initially empty) partition with the build-time \
device_type + persistent mender.conf from a /usr/lib/mender-factory copy, so the \
client has its identity on first boot. Without persistent state the client \
re-keys every boot, re-enrols, and the deployment never commits (hangs in \
'rebooting')."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://mender-swupdate-data-seed.service \
    file://mender-state-debug.service \
"

S = "${UNPACKDIR}"

inherit systemd allarch

RDEPENDS:${PN} += "systemd"
# The seed populates the freshly-mounted (empty) /var/lib/mender on first boot.
# mender-state-debug is a temporary OTA bring-up aid logging the mount + store
# state on each boot.
SYSTEMD_SERVICE:${PN} = "mender-swupdate-data-seed.service mender-state-debug.service"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/mender-swupdate-data-seed.service \
        ${D}${systemd_system_unitdir}/mender-swupdate-data-seed.service
    install -m 0644 ${UNPACKDIR}/mender-state-debug.service \
        ${D}${systemd_system_unitdir}/mender-state-debug.service
}

FILES:${PN} += " \
    ${systemd_system_unitdir}/mender-swupdate-data-seed.service \
    ${systemd_system_unitdir}/mender-state-debug.service \
"
