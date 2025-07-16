DESCRIPTION = "Docker settings for the Docker daemon."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://daemon.json"

RDEPENDS:${PN} = "docker"

do_install() {
    install -d ${D}${sysconfdir}/docker/
    install -m 755 ${WORKDIR}/daemon.json ${D}/${sysconfdir}/docker/daemon.json
}
FILES:${PN} += "${sysconfdir}/docker/daemon.json"
