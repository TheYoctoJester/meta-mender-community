SUMMARY = "/etc/fwumdata.config for our FWU build's two metadata partitions"
DESCRIPTION = "Tells yafwumdata / libfwumdata where to find the FWU metadata: \
the two GPT partitions labelled fwu-mdata-pri and fwu-mdata-sec, each 0xB0 bytes."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fwumdata.config"

RDEPENDS:${PN} = "libfwumdata"

do_install() {
    install -d ${D}${sysconfdir}
    install -m 0644 ${UNPACKDIR}/fwumdata.config ${D}${sysconfdir}/fwumdata.config
}

FILES:${PN} = "${sysconfdir}/fwumdata.config"
