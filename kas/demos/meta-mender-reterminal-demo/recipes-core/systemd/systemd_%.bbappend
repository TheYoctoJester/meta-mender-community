# Disable all logind idle and lid-switch actions for kiosk mode
FILESEXTRAPATHS:prepend:seeed-reterminal-mender := "${THISDIR}/files:"

SRC_URI:append:seeed-reterminal-mender = " file://no-idle.conf"

do_install:append:seeed-reterminal-mender() {
    install -d ${D}${sysconfdir}/systemd/logind.conf.d
    install -m 0644 ${WORKDIR}/no-idle.conf ${D}${sysconfdir}/systemd/logind.conf.d/no-idle.conf
}

FILES:${PN}:append:seeed-reterminal-mender = " ${sysconfdir}/systemd/logind.conf.d/no-idle.conf"
