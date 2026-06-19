DESCRIPTION = "SWU-wrapped main image (the OTA payload)"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit swupdate

# The swupdate class reads this from ${S} (= ${UNPACKDIR}) and substitutes the
# @@VAR@@ tokens (MACHINE, OTA_PARTITION_A/B, SWUPDATE_*_VERSION) itself, so no
# hand-rolled sed task is needed.
SRC_URI = "\
    file://sw-description \
"

# main-image's rootfs is what goes into the .swu
IMAGE_DEPENDS = "main-image"

# images and files that will be included in the .swu image
SWUPDATE_IMAGES = "main-image-${MACHINE}"

# The deployed/symlinked rootfs is main-image-${MACHINE}.rootfs.ext4.gz
# (IMAGE_NAME_SUFFIX = ".rootfs" on wrynose), so the fstype the class searches
# for must include the .rootfs infix. The file lands in the .swu under that
# same basename, which sw-description references.
python() {
  d.appendVarFlag("SWUPDATE_IMAGES_FSTYPES", f"main-image-{d.getVar('MACHINE')}", ".rootfs.ext4.gz")
}
