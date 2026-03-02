FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://psplash-mender-img.png"
SRC_URI:append:seeed-reterminal-mender = " file://psplash-start.conf"

SPLASH_IMAGES:seeed-reterminal-mender = "file://psplash-mender-img.png;outsuffix=default"

do_install:append:seeed-reterminal-mender() {
    # Override meta-raspberrypi's framebuf.conf (broken systemd device dependency)
    # with a version that polls for /dev/fb0 instead
    install -d ${D}${systemd_system_unitdir}/psplash-start.service.d
    install -m 0644 ${WORKDIR}/psplash-start.conf \
        ${D}${systemd_system_unitdir}/psplash-start.service.d/framebuf.conf
}
