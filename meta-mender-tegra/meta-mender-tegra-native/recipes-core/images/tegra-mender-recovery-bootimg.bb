SUMMARY = "Android-style boot image for the Tegra recovery partition"
DESCRIPTION = "Packs the kernel and the recovery initramfs into the boot image format \
that L4TLauncher's BootAndroidStylePartition reads out of the `recovery` partition."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

COMPATIBLE_MACHINE = "(tegra)"
PACKAGE_ARCH = "${MACHINE_ARCH}"

inherit deploy nopackages
inherit ${TEGRA_UEFI_SIGNING_CLASS}

TEGRA_MENDER_RECOVERY_IMAGE ?= "tegra-mender-recovery-initramfs"
TEGRA_MENDER_RECOVERY_BOOTIMG ?= "tegra-mender-recovery.img"

# Serial console LAST. The kernel makes the final console= on the command line
# /dev/console, and a Tegra normally carries both ttyTCU0 and tty0, so the
# obvious ordering puts every message the recovery system prints onto the HDMI
# framebuffer where nobody is looking.
TEGRA_MENDER_RECOVERY_CMDLINE ?= "console=tty0 fbcon=map:0 video=efifb:off console=ttyTCU0,115200"

# The recovery system never switch_roots, so it ignores whatever root= the
# firmware appends. Nothing here needs to name a rootfs slot.

do_compile[depends] += "\
    tegra-flashtools-native:do_populate_sysroot \
    virtual/kernel:do_deploy \
    ${TEGRA_MENDER_RECOVERY_IMAGE}:do_image_complete \
    ${TEGRA_UEFI_SIGNING_TASKDEPS} \
"
do_compile[file-checksums] += "${TEGRA_UEFI_SIGNING_FILECHECKSUMS}"

RECOVERY_PART_SIZE ?= "${TEGRA_RECOVERY_KERNEL_PART_SIZE}"

do_compile() {
    kernel="${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}"
    ramdisk="${DEPLOY_DIR_IMAGE}/${TEGRA_MENDER_RECOVERY_IMAGE}-${MACHINE}.cpio.gz"

    if [ ! -e "$kernel" ]; then
        bbfatal "no kernel image at $kernel"
    fi
    if [ ! -e "$ramdisk" ]; then
        bbfatal "no recovery initramfs at $ramdisk; is ${TEGRA_MENDER_RECOVERY_IMAGE} being built?"
    fi

    ${STAGING_BINDIR_NATIVE}/tegra-flash/mkbootimg \
        --kernel "$kernel" \
        --ramdisk "$ramdisk" \
        --board "recovery" \
        --cmdline '${TEGRA_MENDER_RECOVERY_CMDLINE}' \
        --output ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG}

    # Under UEFI Secure Boot the firmware verifies the boot image before it will
    # run it, exactly as it does for the kernel partition. Use the BSP's own
    # helper so an image built with signing enabled is usable.
    if [ "${TEGRA_UEFI_USE_SIGNED_FILES}" = "true" ]; then
        tegra_uefi_attach_sign ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG}
        rm ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG}
        mv ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG}.signed ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG}
    fi

    size=$(stat -c%s ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG})
    limit="${RECOVERY_PART_SIZE}"
    if [ -z "$limit" ]; then
        bbfatal "RECOVERY_PART_SIZE is empty. It comes from" \
                "TEGRA_RECOVERY_KERNEL_PART_SIZE, which tegra-mender-native.bbclass" \
                "sets globally; without it the size check is meaningless."
    fi
    bbnote "recovery boot image is $size bytes against a $limit byte partition"
    if [ "$size" -gt "$limit" ]; then
        bbfatal "The recovery boot image is $size bytes but the recovery partition" \
                "is only $limit bytes. Either trim TEGRA_MENDER_RECOVERY_INSTALL," \
                "raise TEGRA_RECOVERY_KERNEL_PART_SIZE (which changes the flash" \
                "layout and needs a full reflash), or enable CONFIG_EFI_ZBOOT in" \
                "the kernel, which roughly halves the kernel contribution."
    fi
    # Warn well before it becomes a hard failure, since the recovery system
    # tends to grow one package at a time. Note bitbake's shell parser does not
    # implement $(( )), so this uses expr.
    warn_at=$(expr "$limit" \* 85 / 100)
    if [ "$size" -gt "$warn_at" ]; then
        bbwarn "the recovery boot image is at $size bytes, more than 85% of its" \
               "$limit byte partition"
    fi
}

do_deploy() {
    install -d ${DEPLOYDIR}
    install -m 0644 ${B}/${TEGRA_MENDER_RECOVERY_BOOTIMG} ${DEPLOYDIR}/${TEGRA_MENDER_RECOVERY_BOOTIMG}
}
addtask deploy after do_compile before do_build
