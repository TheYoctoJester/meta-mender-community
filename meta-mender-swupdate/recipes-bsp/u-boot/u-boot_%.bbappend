FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Persist the U-Boot environment in the FAT boot partition so the running
# Linux side (SWUpdate's bootloader handler / libubootenv / fw_setenv) and
# U-Boot itself agree on the "rootpart" A/B selector. qemu virt has no
# MMC/flash, so the stock qemu_arm64_defconfig keeps the env volatile,
# which would lose the slot switch across the reboot. Applied as a config
# fragment (merged by the U-Boot recipe's kconfig handling) rather than a
# version-pinned source patch.
SRC_URI:append = " file://swupdate-uboot.cfg"
