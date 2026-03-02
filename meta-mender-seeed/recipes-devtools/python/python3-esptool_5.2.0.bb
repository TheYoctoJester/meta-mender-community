SUMMARY = "Espressif ESP8266 and ESP32-xx serial bootloader utility"
HOMEPAGE = "https://github.com/espressif/esptool"
LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b234ee4d69f5fce4486a80fdaf4a4263"

SRC_URI[sha256sum] = "9c355b7d6331cc92979cc710ae5c41f59830d1ea29ec24c467c6005a092c06d6"

PYPI_PACKAGE = "esptool"

inherit pypi python_setuptools_build_meta

RDEPENDS:${PN} = " \
    python3-bitstring \
    python3-cryptography \
    python3-pyserial \
    python3-reedsolo \
    python3-pyyaml \
    python3-intelhex \
    python3-rich-click \
    python3-click \
"
