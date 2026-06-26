# meta-mender's mender-setup.bbclass globally renames every image by
# MENDER_DEVICE_TYPE:
#     IMAGE_NAME      = "${IMAGE_BASENAME}-${MENDER_DEVICE_TYPE}${IMAGE_VERSION_SUFFIX}"
#     IMAGE_LINK_NAME = "${IMAGE_BASENAME}-${MENDER_DEVICE_TYPE}"
#
# The UKI demo sets a distinct MENDER_DEVICE_TYPE (qemuarm64-uki) so the OTA
# test can tell it apart from the FWU demo, which would name this initramfs
# core-image-minimal-initramfs-qemuarm64-uki.cpio.gz. But oe-core's do_uki
# (and the demo's do_uki_b) look the initramfs up by MACHINE
# (core-image-minimal-initramfs-qemuarm64-secureboot.cpio.gz), so the mismatch
# made do_uki fail with "initramfs image was not deployed".
#
# The initramfs is not a Mender artifact, so restore stock MACHINE-based naming
# for it. Applies wherever this image is built, including the uki-initramfs
# multiconfig.
IMAGE_NAME = "${IMAGE_BASENAME}-${MACHINE}${IMAGE_VERSION_SUFFIX}"
IMAGE_LINK_NAME = "${IMAGE_BASENAME}-${MACHINE}"
