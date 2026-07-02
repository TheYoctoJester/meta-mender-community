SUMMARY = "OSTree-based demo rootfs managed by the Mender client (client-only)"
DESCRIPTION = "core-image-minimal turned into an OSTree deployment (via sota / \
meta-updater) with the Mender client in client-only mode. A custom 'ostree' \
Update Module applies OSTree static deltas delivered inside Mender artifacts."
LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

# Mender client (client-only; mender-full is off) + the OSTree tooling the
# Update Module needs at runtime, + U-Boot env tools. The 'ostree' package and
# the OSTree deployment layout come from meta-updater's sota integration.
IMAGE_INSTALL:append = " \
    ostree \
    mender-auth \
    mender-update \
    u-boot-fw-utils \
"

IMAGE_FEATURES += "ssh-server-openssh"

# Only the demo image builds the wic (OSTree sysroot via --source otaimage).
# Setting this per-image, not on the machine, keeps meta-updater's
# initramfs-ostree-image from also building a wic (which is a circular dep).
IMAGE_FSTYPES:append = " wic wic.bmap"
