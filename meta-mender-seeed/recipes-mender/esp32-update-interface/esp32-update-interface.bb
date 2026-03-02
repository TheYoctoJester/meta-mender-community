SUMMARY = "ESP32 update interface for Mender Orchestrator"
DESCRIPTION = "Custom interface that flashes ESP32 firmware via esptool over USB serial"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = " \
    file://esp32 \
    file://esp32-devices.conf \
    file://99-esp32-usb.rules \
"

RDEPENDS:${PN} = "python3-esptool jq"

do_install() {
    # Interface script
    install -d ${D}${datadir}/mender-orchestrator/interfaces/v1
    install -m 0755 ${WORKDIR}/esp32 ${D}${datadir}/mender-orchestrator/interfaces/v1/esp32

    # Device mapping config
    install -d ${D}${sysconfdir}/mender-orchestrator
    install -m 0644 ${WORKDIR}/esp32-devices.conf ${D}${sysconfdir}/mender-orchestrator/esp32-devices.conf

    # Udev rules
    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/99-esp32-usb.rules ${D}${sysconfdir}/udev/rules.d/99-esp32-usb.rules
}

FILES:${PN} = " \
    ${datadir}/mender-orchestrator/interfaces/v1/esp32 \
    ${sysconfdir}/mender-orchestrator/esp32-devices.conf \
    ${sysconfdir}/udev/rules.d/99-esp32-usb.rules \
"
