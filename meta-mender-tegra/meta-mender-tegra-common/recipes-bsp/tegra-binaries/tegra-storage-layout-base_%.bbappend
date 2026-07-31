require tegra-mender-layout.inc

DEPENDS:append = " tegra-helper-scripts-native"
PATH =. "${STAGING_BINDIR_NATIVE}/tegra-flash:"

mender_flash_layout_adjust() {
    local file=$1
    mv ${D}${datadir}/l4t-storage-layout/$file ${WORKDIR}/$file
    nvflashxmlparse -v --rewrite-contents-from=${WORKDIR}/UDA.xml \
		--output=${D}${datadir}/l4t-storage-layout/$file \
		${WORKDIR}/$file
}

do_install:append() {
    mender_flash_layout_write_map ${WORKDIR}/UDA.xml \
        ${TEGRA_MENDER_LAYOUT_FILENAMES} ${TEGRA_MENDER_LAYOUT_FILENAMES_EXTRA}

    mender_flash_layout_adjust "${PARTITION_LAYOUT_TEMPLATE}"
    mender_flash_layout_adjust "${PARTITION_LAYOUT_EXTERNAL}"
    chown -R root:root ${D}
}
