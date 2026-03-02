FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://topology.yaml"

FILES:${PN} += "/data/mender-orchestrator/topology.yaml"

do_install:append() {
    install -d ${D}/data/mender-orchestrator
    install -m 0644 ${WORKDIR}/topology.yaml ${D}/data/mender-orchestrator/topology.yaml
}
