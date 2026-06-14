SUMMARY = "Library to access Firmware Update (FWU) metadata"

DESCRIPTION = "This package contains a library to read and modify FWU \
metadata. It provides a minimal API to allow userspace applications, such as \
SWUpdate, RAUC or any other OTA update manager, to modify the boot bank \
selection."

HOMEPAGE = "https://github.com/passgat/libfwumdata"
LICENSE = "LGPL-2.1-or-later"
LIC_FILES_CHKSUM = "file://LICENSES/LGPL-2.1-or-later.txt;md5=4fbd65380cdd255951079008b364516c"
SECTION = "libs"

SRC_URI = " \
    git://github.com/passgat/libfwumdata;protocol=https;branch=master \
    file://0001-set-bank-state-v1-accept.patch \
    "
SRCREV = "c6e235d3cf0467211ca6946bd10a2c8bdc0d5053"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

inherit cmake lib_package

DEPENDS = "zlib"

# libfwumdata's CMakeLists.txt uses bare add_library() which defaults
# to static. Force a proper shared build so the main libfwumdata
# package is non-empty.
EXTRA_OECMAKE = "-DBUILD_SHARED_LIBS=ON"

BBCLASSEXTEND = "native"
