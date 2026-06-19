FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://09-swupdate-args.in \
    file://swupdate.cfg \
    file://fw_env.config \
    file://defconfig \
"

do_swupdate_args_update() {
    # Yocto dependency checking can be broken if we modify the source file
    # directly during the build process, create a 'output' file to modify
    cp ${WORKDIR}/09-swupdate-args.in ${WORKDIR}/09-swupdate-args
    sed -i -e "s%__SWUPDATE_HARDWARE_VERSION%${SWUPDATE_HARDWARE_VERSION}%" ${WORKDIR}/09-swupdate-args
    sed -i -e "s%__OTA_PARTITION_A%${OTA_PARTITION_A}%" ${WORKDIR}/09-swupdate-args

	echo "${MACHINE} ${SWUPDATE_HARDWARE_VERSION}" > ${WORKDIR}/hwrevision
}
addtask do_swupdate_args_update before do_install after do_unpack


do_install:append() {
    install -Dm 0644 ${WORKDIR}/09-swupdate-args ${D}${libdir}/swupdate/conf.d/09-swupdate-args
    install -Dm 0644 ${WORKDIR}/swupdate.cfg ${D}${sysconfdir}/swupdate.cfg

    install -Dm 0644 ${WORKDIR}/hwrevision ${D}${sysconfdir}/hwrevision

    # /etc/fw_env.config (CONFIG_UBOOT_FWENV): libubootenv (used by
    # SWUpdate's U-Boot bootloader handler) and fw_setenv both read this
    # to locate the U-Boot env -- here, uboot.env in the FAT boot
    # partition mounted at /boot.
    install -Dm 0644 ${WORKDIR}/fw_env.config ${D}${sysconfdir}/fw_env.config
}

FILES:${PN} += "${sysconfdir}/fw_env.config"

# Buffered iteration installs one-shot via "swupdate -i" from the update
# module, so the swupdate daemon is not needed. The streaming iteration
# enables it (see layer README).
SYSTEMD_AUTO_ENABLE = "disable"
