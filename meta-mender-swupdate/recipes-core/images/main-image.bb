require recipes-core/images/core-image-minimal.bb

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# The flashed rootfs (also the payload SWUpdate writes to the inactive
# slot). Mender client (client-only) + our 'swu' Update Module +
# SWUpdate + the U-Boot env tooling that backs the A/B selector.
IMAGE_INSTALL:append = " \
    mender-auth \
    mender-update \
    mender-connect \
    mender-update-module-swupdate \
    swupdate \
    u-boot-fw-utils \
    u-boot-env \
"
