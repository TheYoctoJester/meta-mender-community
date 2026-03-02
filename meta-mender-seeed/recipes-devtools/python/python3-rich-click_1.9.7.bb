SUMMARY = "Rich-click provides beautiful help output for click CLI applications using Rich"
HOMEPAGE = "https://github.com/ewels/rich-click"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=5372b77c3720be60b7eff9a9a5c0000d"

SRC_URI[sha256sum] = "022997c1e30731995bdbc8ec2f82819340d42543237f033a003c7b1f843fc5dc"

PYPI_PACKAGE = "rich_click"

inherit pypi python_setuptools_build_meta

RDEPENDS:${PN} = " \
    python3-click \
    python3-rich \
"
