require recipes-core/images/core-image-minimal.bb

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# The flashed rootfs (also the payload SWUpdate writes to the inactive
# slot). Mender client (client-only) + our 'swu' Update Module +
# SWUpdate + the U-Boot env tooling that backs the A/B selector.
# mender-connect (remote terminal) is intentionally omitted: it is not part of
# the SWUpdate OTA demo, and mender-connect 3.0.0 on this meta-mender fails
# do_package ("Didn't find service unit mender-connect.service") regardless of
# the systemd DISTRO_FEATURE. The qemuarm64-rauc demo likewise ships without it.
IMAGE_INSTALL:append = " \
    mender-auth \
    mender-update \
    mender-update-module-swupdate \
    mender-swupdate-data \
    swupdate \
    u-boot-fw-utils \
    u-boot-env \
"

# DEBUG AID (OTA bring-up): forward the journal to the serial console so the
# mender-auth / mender-update state-machine logs (which otherwise only go to
# journald) are visible in the captured runqemu serial -- needed to see why the
# post-reboot ArtifactCommit does not complete. Remove once the OTA is green.
ROOTFS_POSTPROCESS_COMMAND += "swupdate_forward_journal_to_console;"
swupdate_forward_journal_to_console() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/journald.conf.d
    cat > ${IMAGE_ROOTFS}${sysconfdir}/systemd/journald.conf.d/forward-to-console.conf <<'EOF'
[Journal]
ForwardToConsole=yes
MaxLevelConsole=info
EOF
}
