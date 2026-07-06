SUMMARY = "Mender Update Module 'swu' that drives the SWUpdate client"
DESCRIPTION = "Installs the 'swu' Mender Update Module: a Mender Artifact \
of payload type 'swu' carries a SWUpdate .swu image, and this module hands \
that .swu to the on-device SWUpdate client, which performs the actual A/B \
rootfs write and sets the U-Boot 'rootpart' selector. This is the buffered \
iteration -- the staged .swu is installed one-shot with 'swupdate -i'. The \
streaming iteration (Download state piping the payload into swupdate-client \
over the IPC socket) is documented in the layer README."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://swu"

# Runtime deps used by the module script:
#   bash               - the script interpreter
#   jq                 - parse the optional .reboot flag from header/meta-data
#   util-linux-findmnt - determine the currently booted rootfs slot
#   swupdate           - the installer the module drives (swupdate -i)
RDEPENDS:${PN} = " \
    bash \
    jq \
    util-linux-findmnt \
    swupdate \
    "

# v3 update modules live here for mender-update 5.x (same across the demos).
MENDER_MODULES_DIR = "${datadir}/mender/modules/v3"

do_install() {
    install -d "${D}${MENDER_MODULES_DIR}"
    install -m 0755 ${UNPACKDIR}/swu "${D}${MENDER_MODULES_DIR}/swu"
}

FILES:${PN} = "${MENDER_MODULES_DIR}/swu"
