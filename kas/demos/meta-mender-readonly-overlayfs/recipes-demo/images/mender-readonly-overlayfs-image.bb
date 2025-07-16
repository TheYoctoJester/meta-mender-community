require recipes-extended/images/core-image-full-cmdline.bb

IMAGE_INSTALL:append = " docker-overlayfs "
IMAGE_FEATURES:append = " read-only-rootfs "