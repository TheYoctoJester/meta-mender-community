SUMMARY = "OS-side glue for Mender on a barebox system"
DESCRIPTION = "Wires the userspace half of the Mender + barebox A/B demo. \
Unlike the systemd-boot / UKI demos there is no fw_setenv/fw_printenv shim: \
barebox reads the very same U-Boot-format environment that the stock \
libubootenv tools write, so this recipe only ships the /etc/fw_env.config that \
points libubootenv at the raw env partition (the same partition barebox' \
ubootvar driver reads via its device-tree node). It also ships a tmpfiles \
snippet + a var-lib-mender.mount unit that bind-mount /data/mender over \
/var/lib/mender before the mender services start, so the Mender state DB and \
the agent key survive the rootfs swap of an OTA."

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://fw_env.config \
    file://mender-barebox-data.conf \
    file://var-lib-mender.mount \
"

S = "${UNPACKDIR}"

# The raw U-Boot env partition as seen from the running OS. Set per machine in
# the kas wrapper (e.g. /dev/mmcblk0p5 on RPi4, /dev/vda5 on qemuarm64); it must
# name the same partition the barebox uboot-environment device-tree node points
# at.
BAREBOX_MENDER_ENV_DEVICE ?= "/dev/mmcblk0p5"

# Stock libubootenv provides fw_setenv/fw_printenv; systemd owns the mount unit.
RDEPENDS:${PN} += "libubootenv-bin systemd"

SYSTEMD_SERVICE:${PN} = "var-lib-mender.mount"
inherit systemd

do_install() {
    install -d ${D}${sysconfdir}
    sed -e 's|@ENV_DEVICE@|${BAREBOX_MENDER_ENV_DEVICE}|g' \
        ${UNPACKDIR}/fw_env.config > ${D}${sysconfdir}/fw_env.config

    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${UNPACKDIR}/mender-barebox-data.conf \
        ${D}${libdir}/tmpfiles.d/mender-barebox-data.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/var-lib-mender.mount \
        ${D}${systemd_system_unitdir}/var-lib-mender.mount
}

FILES:${PN} += " \
    ${sysconfdir}/fw_env.config \
    ${libdir}/tmpfiles.d/mender-barebox-data.conf \
    ${systemd_system_unitdir}/var-lib-mender.mount \
"

# Note: oe-core's libubootenv-bin ships fw_env.config only as a sample, not at
# /etc, so installing ours here does not clash. If meta-mender's libubootenv
# bbappend is changed to install /etc/fw_env.config, resolve the conflict (e.g.
# update-alternatives) rather than letting do_rootfs fail.

