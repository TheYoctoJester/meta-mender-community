# Puts the recovery boot image into the tegraflash package, so that flashing a
# board populates the `recovery` partition.
#
# The partition itself is created by meta-tegra on nearly every Tegra layout and
# then left empty, because image_types_tegra.bbclass:298 deletes the RECFILE
# line that would give it content. The companion piece to this class is the
# tegra-storage-layout-base bbappend, which puts a literal filename into the
# staged layout so that deletion has nothing to match.
#
# Only the file staging lives here. Everything about how the image is built is
# in tegra-mender-recovery-bootimg.bb.

# TEGRA_MENDER_RECOVERY_BOOTIMG comes from tegra-mender-native, which is global,
# because the tegra-storage-layout-base bbappend needs the same name and cannot
# see a recipe class.

# IMAGE_CLASSES applies to every image recipe, including the recovery initramfs
# itself. That one has no tegraflash-tar output, so the staging below never
# runs for it, but the dependency would still be declared and points back at a
# recipe that depends on the recovery initramfs: a cycle waiting to happen.
# Skip it explicitly rather than relying on bitbake to ignore a dependency on a
# task that does not exist.
TEGRA_MENDER_RECOVERY_SKIP_IMAGES ?= "tegra-mender-recovery-initramfs initramfs espimage"

# tegra_mender_image_wanted comes from tegra-mender-native, which is global, so it
# is available here and in every recipe this class reaches.
def tegra_mender_recovery_applies(d):
    return tegra_mender_image_wanted(d, 'TEGRA_MENDER_RECOVERY_SKIP_IMAGES')

do_image_tegraflash_tar[depends] += "${@'tegra-mender-recovery-bootimg:do_deploy' if tegra_mender_recovery_applies(d) else ''}"

# create_tegraflash_pkg calls this after it has assembled the kernel, ESP and
# rootfs, and before it generates the flash configuration, so a file dropped
# here is in place by the time the layout is read.
tegraflash_custom_pre:append() {
    if ! ${@'true' if tegra_mender_recovery_applies(d) else 'false'}; then
        return
    fi
    if [ ! -e "${DEPLOY_DIR_IMAGE}/${TEGRA_MENDER_RECOVERY_BOOTIMG}" ]; then
        bbfatal "TEGRA_MENDER_RECOVERY is enabled but" \
                "${DEPLOY_DIR_IMAGE}/${TEGRA_MENDER_RECOVERY_BOOTIMG} does not exist."
    fi
    cp "${DEPLOY_DIR_IMAGE}/${TEGRA_MENDER_RECOVERY_BOOTIMG}" ./${TEGRA_MENDER_RECOVERY_BOOTIMG}
    bbnote "staged ${TEGRA_MENDER_RECOVERY_BOOTIMG} into the tegraflash package"
}
