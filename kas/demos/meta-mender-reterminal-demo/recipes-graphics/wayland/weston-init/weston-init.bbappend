# For the reTerminal, provide a kiosk-mode weston.ini.
# The reterminal/ subdirectory is prepended to the file search path,
# so the base recipe's fetch of file://weston.ini will find our version.
FILESEXTRAPATHS:prepend:seeed-reterminal-mender := "${THISDIR}/reterminal:"

# Disable Weston idle timeout via PACKAGECONFIG (belt-and-suspenders with weston.ini)
PACKAGECONFIG:append:seeed-reterminal-mender = " no-idle-timeout"

# Install a systemd service that disables kernel-level console blanking and DPMS
SRC_URI:append:seeed-reterminal-mender = " file://disable-screen-blanking.service"

inherit systemd

SYSTEMD_SERVICE:${PN}:append:seeed-reterminal-mender = " disable-screen-blanking.service"

do_install:append:seeed-reterminal-mender() {
    install -D -m 0644 ${WORKDIR}/disable-screen-blanking.service \
        ${D}${systemd_system_unitdir}/disable-screen-blanking.service
}

FILES:${PN}:append:seeed-reterminal-mender = " ${systemd_system_unitdir}/disable-screen-blanking.service"
