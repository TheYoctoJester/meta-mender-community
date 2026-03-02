SUMMARY = "Mender Monitor button-press alerts for reTerminal"
DESCRIPTION = "Systemd service that streams reTerminal GPIO key events \
to a log file, plus mender-monitor check definitions that trigger alerts \
when F1, F2, F3, or O buttons are pressed."
HOMEPAGE = "https://github.com/mendersoftware/meta-mender-community"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://find-gpio-keys.sh \
    file://button-event-logger.sh \
    file://button-event-logger.service \
    file://log_button_f1.sh \
    file://log_button_f2.sh \
    file://log_button_f3.sh \
    file://log_button_o.sh \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash evtest mender-monitor"

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

    # Install mender-monitor check definitions
    install -d ${D}${sysconfdir}/mender-monitor/monitor.d/available
    install -d ${D}${sysconfdir}/mender-monitor/monitor.d/enabled
    for check in log_button_f1.sh log_button_f2.sh log_button_f3.sh log_button_o.sh; do
        install -m 0644 ${WORKDIR}/${check} \
            ${D}${sysconfdir}/mender-monitor/monitor.d/available/
        ln -sf ../available/${check} \
            ${D}${sysconfdir}/mender-monitor/monitor.d/enabled/${check}
    done
}

FILES:${PN} = " \
    /opt/mender-monitor-buttons \
    ${systemd_system_unitdir}/button-event-logger.service \
    ${sysconfdir}/mender-monitor \
"
