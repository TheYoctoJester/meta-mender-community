SUMMARY = "Early module loading for reTerminal MIPI DSI panel driver"
DESCRIPTION = "Loads mipi_dsi.ko via systemd-modules-load.service instead of \
waiting for udev coldplug, shaving ~700ms off time-to-first-display."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://mipi-dsi.conf"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/modules-load.d
    install -m 0644 ${WORKDIR}/mipi-dsi.conf ${D}${sysconfdir}/modules-load.d/mipi-dsi.conf
}

FILES:${PN} = "${sysconfdir}/modules-load.d/mipi-dsi.conf"
