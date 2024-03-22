require u-boot-common.inc
require u-boot.inc

DEPENDS += "bc-native dtc-native python3-pyelftools-native"

COMPATIBLE_MACHINE = "raspberrypi5"

SRC_URI:append = " \
	file://0001-RPi-5-DTB.patch \
	file://0002-i-think-this-is-where-rp1-is-meant-to-go.patch \
	file://0003-dtsi.patch \
"