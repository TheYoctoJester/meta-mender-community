require recipes-core/images/core-image-minimal.bb

DESCRIPTION = "A small image capable of testing a Mender board integration"

IMAGE_FEATURES:append = " allow-empty-password empty-root-password allow-root-login "
IMAGE_INSTALL:append = " bootloader-validation "
