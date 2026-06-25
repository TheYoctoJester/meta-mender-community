# meta-mender-uki: keep the initramfs deploy artifact present for do_uki.
#
# The qemuarm64-uki demo's do_uki / do_uki_b consume this initramfs's deployed
# .cpio.gz by its link name in DEPLOY_DIR_IMAGE. do_image_complete is an sstate
# task whose stamp records that the image was completed; but in the persistent
# CI build dir the deployed artifacts can be pruned (disk reclaim) while that
# stamp survives. bitbake then neither re-runs nor setscene-restores the image,
# so the .cpio.gz stays missing and do_uki dies with "initramfs image was not
# deployed" (runs #2361-#2363, confirmed by the do_uki prefunc diagnostics).
#
# Force do_image_complete to run every build: the real task re-copies the
# staged image (IMGDEPLOYDIR) into DEPLOY_DIR_IMAGE and recreates the symlink,
# so the artifact is always present regardless of any deploy-dir pruning. Keep
# this image's work dir out of rm_work so that staging source persists across
# runs. The initramfs is small and do_image_complete is just a copy, so the
# cost is negligible. Scoped to the UKI demo (sole consumer of meta-mender-uki).
do_image_complete[nostamp] = "1"
RM_WORK_EXCLUDE += "core-image-minimal-initramfs"
