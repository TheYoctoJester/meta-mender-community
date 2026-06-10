SUMMARY = "Mender artifact wrapping the RAUC update bundle"
DESCRIPTION = "Packages the signed RAUC bundle (update-bundle-*.raucb, produced \
by meta-rauc-qemuarm) into a Mender artifact of payload type 'rauc', deployable \
from the Mender server and installed by the 'rauc' update module."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit nopackages deploy

DEPENDS = "mender-artifact-native update-bundle"

# Source bundle produced by meta-rauc-qemuarm's update-bundle recipe.
RAUC_BUNDLE_FILE ?= "update-bundle-${MACHINE}.raucb"

# Must differ from the artifact name provisioned in the running rootfs so the
# deployment is seen as an update. Override per release.
MENDER_RAUC_ARTIFACT_NAME ?= "rauc-${MACHINE}-2"

# Payload type - must match the update module name installed on the device.
MENDER_RAUC_PAYLOAD_TYPE ?= "rauc"

do_deploy() {
    mender-artifact write module-image \
        -T "${MENDER_RAUC_PAYLOAD_TYPE}" \
        -t "${MACHINE}" \
        -n "${MENDER_RAUC_ARTIFACT_NAME}" \
        -f "${DEPLOY_DIR_IMAGE}/${RAUC_BUNDLE_FILE}" \
        -o "${DEPLOYDIR}/${MENDER_RAUC_ARTIFACT_NAME}.mender"
}

# deploy.bbclass sets up the sstate flags but does not schedule do_deploy;
# the recipe must (cf. u-boot, kernel recipes).
addtask do_deploy before do_build after do_compile
do_deploy[depends] += "update-bundle:do_deploy mender-artifact-native:do_populate_sysroot"
