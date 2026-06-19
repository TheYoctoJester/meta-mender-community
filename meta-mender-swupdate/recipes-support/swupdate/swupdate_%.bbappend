FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://swupdate.cfg \
    file://fw_env.config \
    file://defconfig \
"

do_install:append() {
    install -d ${D}${sysconfdir}

    install -m 0644 ${UNPACKDIR}/swupdate.cfg ${D}${sysconfdir}/swupdate.cfg

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

FILES:${PN} += "${sysconfdir}/swupdate.cfg ${sysconfdir}/fw_env.config ${sysconfdir}/hwrevision"

# The swupdate 2026.05 binary embeds a build-path (TMPDIR) reference, which the
# (now-fatal) buildpaths reproducibility QA check rejects. This is upstream
# meta-swupdate behaviour, not a functional problem; skip the check for the
# swupdate package in this demo.
INSANE_SKIP:${PN} += "buildpaths"

# Buffered iteration installs one-shot via "swupdate -i" from the update
# module, so the swupdate daemon is not needed. The streaming iteration enables
# it and adds /usr/lib/swupdate/conf.d/09-swupdate-args (see the layer README).
SYSTEMD_AUTO_ENABLE = "disable"
