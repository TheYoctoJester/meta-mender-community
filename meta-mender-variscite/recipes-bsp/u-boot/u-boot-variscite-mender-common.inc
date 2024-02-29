FILESEXTRAPATHS:prepend := "${THISDIR}/patches:"

SRC_URI:append:imx8mm-var-dart = " \
    file://imx8mm_var_dart_defconfig.mender.patch \
    file://imx8mm_var_dart.h.mender.patch \
"

MENDER_UBOOT_CONFIG_SYS_MMC_ENV_PART:imx8mm-var-dart = "0"
MENDER_UBOOT_STORAGE_DEVICE:imx8mm-var-dart = "${@ "1" if "sd" == d.getVar("UBOOT_CONFIG") else "0" }"
BOOTENV_SIZE:imx8mm-var-dart = "0x4000"
MENDER_UBOOT_ENV_STORAGE_DEVICE_OFFSET:imx8mm-var-dart = "0x400000"
MENDER_UBOOT_ENV_STORAGE_DEVICE_OFFSET_2:imx8mm-var-dart = "0x440000"

SRC_URI:append:imx93-var-som = " \
    file://0001-u-boot-variscite-configuration-adjustments-for-Mende.patch \
    file://0002-u-boot-variscite-Mender-integration-to-bootcmd.patch \
"

MENDER_UBOOT_STORAGE_DEVICE:imx93-var-som = "1"
MENDER_UBOOT_CONFIG_SYS_MMC_ENV_PART:imx93-var-som = "0"
MENDER_UBOOT_ENV_STORAGE_DEVICE_OFFSET:imx93-var-som = "0x700000"
MENDER_UBOOT_ENV_STORAGE_DEVICE_OFFSET_2:imx93-var-som = "0x740000"