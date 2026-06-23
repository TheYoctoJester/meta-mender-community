FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://swupdate.cfg \
    file://fw_env.config \
    file://defconfig \
    file://10-swupdate-args \
"

do_install:append() {
    install -d ${D}${sysconfdir}

    install -m 0644 ${UNPACKDIR}/swupdate.cfg ${D}${sysconfdir}/swupdate.cfg

    # Daemon args allow-list (sourced by swupdate.sh): permit the A/B
    # sw-description selections for IPC installs (see file header).
    install -d ${D}${libdir}/swupdate/conf.d
    install -m 0644 ${UNPACKDIR}/10-swupdate-args ${D}${libdir}/swupdate/conf.d/10-swupdate-args

    # /etc/fw_env.config (CONFIG_UBOOT_FWENV): libubootenv (used by SWUpdate's
    # U-Boot bootloader handler) reads this to locate the U-Boot env -- here,
    # uboot.env in the FAT boot partition mounted at /boot.
    install -m 0644 ${UNPACKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config

    # /etc/hwrevision (CONFIG_HW_COMPATIBILITY_FILE): the board + revision that
    # SWUpdate matches against the sw-description board section (@@MACHINE@@)
    # and its hardware-compatibility list. The swu Update Module relies on this
    # rather than passing -H.
    echo "${MACHINE} ${SWUPDATE_HARDWARE_VERSION}" > ${D}${sysconfdir}/hwrevision
}

FILES:${PN} += "${sysconfdir}/swupdate.cfg ${sysconfdir}/fw_env.config ${sysconfdir}/hwrevision ${libdir}/swupdate/conf.d/10-swupdate-args"

# The swupdate 2026.05 binary embeds a build-path (TMPDIR) reference, which the
# (now-fatal) buildpaths reproducibility QA check rejects. This is upstream
# meta-swupdate behaviour, not a functional problem; skip the check for the
# swupdate package in this demo.
INSANE_SKIP:${PN} += "buildpaths"

# Streaming iteration: run SWUpdate as a daemon so the swu Update Module can
# stream the payload into it over the IPC control socket (/tmp/sockinstctrl)
# during Mender's Download state. swupdate.service runs swupdate.sh -> swupdate
# with no -i and no webserver/suricatta args (we ship no conf.d/* mode), i.e. a
# plain IPC-listening daemon. swupdate-client (shipped by the swupdate-client
# package, installed in main-image) connects to that socket.
#
# Enable ONLY swupdate.service (the standalone daemon), NOT swupdate.socket:
# meta-swupdate ships both, but enabling both makes the boot-started daemon and
# systemd's socket unit both try to own /tmp/sockinstctrl -> the daemon cannot
# bind it -> swupdate-client gets "swupdate_async_start returns -1" (seen in run
# #2336). With only the standalone service, the daemon creates + owns the socket
# and the client connects cleanly.
SYSTEMD_SERVICE:${PN} = "swupdate.service"
SYSTEMD_AUTO_ENABLE = "enable"
