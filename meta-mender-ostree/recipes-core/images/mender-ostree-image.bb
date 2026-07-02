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
    mender-ostree-data \
"

IMAGE_FEATURES += "ssh-server-openssh"

# OSTree empties /var of deployment content, so /var/lib/mender (device_type,
# mender.conf, agent key/state) installed by the client recipes would be missing
# at runtime. Stash it into /usr/lib/mender-factory (in /usr, carried read-only
# by the OSTree deployment) before do_image's OSTree-ification runs; the
# mender-ostree-data seed service copies it back into the persistent /var on
# first boot. Runs at end of do_rootfs, while /var/lib/mender still exists.
mender_ostree_stash_factory() {
    install -d ${IMAGE_ROOTFS}/usr/lib/mender-factory
    if [ -d ${IMAGE_ROOTFS}${localstatedir}/lib/mender ]; then
        cp -a ${IMAGE_ROOTFS}${localstatedir}/lib/mender/. ${IMAGE_ROOTFS}/usr/lib/mender-factory/
    fi
}
ROOTFS_POSTPROCESS_COMMAND += "mender_ostree_stash_factory;"

# Only the demo image builds the wic (OSTree sysroot via --source otaimage).
# Setting this per-image, not on the machine, keeps meta-updater's
# initramfs-ostree-image from also building a wic (which is a circular dep).
IMAGE_FSTYPES:append = " wic wic.bmap"
