DESCRIPTION = "Build the flashable main-image and the SWU OTA payload together"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Meta-target only: it produces no rootfs of its own, so it deliberately does
# NOT inherit image. Inheriting image on wrynose pulls in the SPDX image class
# (do_create_rootfs_spdx etc.), which then fails because there is no rootfs to
# describe. Instead just depend on both real deliverables so `bitbake
# all-images` builds the flashable wic (main-image) and the OTA payload
# (swu-image).
inherit nopackages

do_build[depends] += "main-image:do_image_complete swu-image:do_swuimage"
