FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI += "file://Download_Leave_10 \
            file://ArtifactInstall_Enter_10 \
"
inherit allarch
inherit mender-state-scripts

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install() {
    # this will be bundled into the image
    install -m 444 ${WORKDIR}/Download_Leave_10 ${MENDER_STATE_SCRIPTS_DIR}/Download_Leave_10

    # this will be bundled into the artifact
    install -m 444 ${WORKDIR}/ArtifactInstall_Enter_10 ${MENDER_STATE_SCRIPTS_DIR}/ArtifactInstall_Enter_10
}
