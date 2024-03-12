require recipes-extended/images/core-image-full-cmdline.bb

IMAGE_INSTALL:append = " \
	mender-app-update \
	packagegroup-k3s-host \
	packagegroup-k3s-node \
	ca-certificates \
	kernel-modules \
"