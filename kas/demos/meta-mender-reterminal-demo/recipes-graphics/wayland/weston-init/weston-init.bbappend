# For the reTerminal, provide a kiosk-mode weston.ini and anti-blanking service.
FILESEXTRAPATHS:prepend:seeed-reterminal-mender := "${THISDIR}/reterminal:"

# Install a systemd service that disables kernel-level console blanking and DPMS
SRC_URI:append:seeed-reterminal-mender = " file://disable-screen-blanking.service file://kiosk-weston.ini"

inherit systemd

SYSTEMD_SERVICE:${PN}:append:seeed-reterminal-mender = " disable-screen-blanking.service"

do_install:append:seeed-reterminal-mender() {
    # Overwrite default weston.ini with kiosk configuration
    install -m 0644 ${WORKDIR}/kiosk-weston.ini ${D}${sysconfdir}/xdg/weston/weston.ini

    install -D -m 0644 ${WORKDIR}/disable-screen-blanking.service \
        ${D}${systemd_system_unitdir}/disable-screen-blanking.service
}

FILES:${PN}:append:seeed-reterminal-mender = " ${systemd_system_unitdir}/disable-screen-blanking.service"
