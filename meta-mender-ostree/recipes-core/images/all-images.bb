SUMMARY = "Meta-target: build the OSTree demo image (and, later, its v2 delta)"
LICENSE = "MIT"

# Not an image itself (avoids inheriting image/SPDX just to be a build handle),
# mirrors meta-mender-swupdate's all-images. Builds the demo rootfs; the
# build-time v2 static-delta payload target is added here once that recipe
# exists (Update Module phase).
do_build[depends] = "mender-ostree-image:do_image_complete"
do_build[noexec] = "1"

INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"
