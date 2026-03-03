SUMMARY = "Mender Monitor button-press alerts for reTerminal"
DESCRIPTION = "Systemd service that monitors reTerminal GPIO key presses \
and sends toggle alerts (set/clear) directly to the Mender server \
for F1, F2, F3, and O buttons."
HOMEPAGE = "https://github.com/mendersoftware/meta-mender-community"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://find-gpio-keys.sh \
    file://button-event-logger.sh \
    file://button-event-logger.service \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "evtest curl"

inherit systemd

SYSTEMD_SERVICE:${PN} = "button-event-logger.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    # Install scripts
    install -d ${D}/opt/mender-monitor-buttons
    install -m 0755 ${WORKDIR}/find-gpio-keys.sh ${D}/opt/mender-monitor-buttons/
    install -m 0755 ${WORKDIR}/button-event-logger.sh ${D}/opt/mender-monitor-buttons/

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/button-event-logger.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    /opt/mender-monitor-buttons \
    ${systemd_system_unitdir}/button-event-logger.service \
"
