DEPENDS:append = " tegra-helper-scripts-native"
PATH =. "${STAGING_BINDIR_NATIVE}/tegra-flash:"

# The partition in NVIDIA's staged layouts that receives the mender data image.
# NVIDIA owns these names, so this is the one thing no MENDER_ variable can
# supply: it is the same per-machine statement as MENDER_DATA_PART_NUMBER_DEFAULT
# in tegra-mender-common.bbclass, made in the layout's terms rather than Linux's.
# Both rewrites below are keyed on it, so the two cannot drift apart.
TEGRA_MENDER_DATA_PART_NAME ?= "UDA"

mender_flash_layout_adjust() {
    local file=$1
    mv ${D}${datadir}/l4t-storage-layout/$file ${WORKDIR}/$file
    nvflashxmlparse -v --rewrite-contents-from=${WORKDIR}/UDA.xml \
		--output=${WORKDIR}/$file.contents \
		${WORKDIR}/$file
    nvflashxmlparse -v --update-parttype-sizes-from=${WORKDIR}/UDA-size.xml:data \
		--output=${D}${datadir}/l4t-storage-layout/$file \
		${WORKDIR}/$file.contents
}

do_install:append() {
    cat <<EOF >${WORKDIR}/UDA.xml
<partition_layout>
    <device>
        <partition name="${TEGRA_MENDER_DATA_PART_NAME}">
            <filename> DATAFILE </filename>
        </partition>
    </device>
</partition_layout>
EOF

    cat <<EOF >${WORKDIR}/UDA-size.xml
<partition_layout>
    <device>
        <partition name="${TEGRA_MENDER_DATA_PART_NAME}">
            <size> ${@int(d.getVar('MENDER_DATA_PART_SIZE_MB')) * 1024 * 1024} </size>
        </partition>
    </device>
</partition_layout>
EOF

    mender_flash_layout_adjust "${PARTITION_LAYOUT_TEMPLATE}"
    mender_flash_layout_adjust "${PARTITION_LAYOUT_EXTERNAL}"
    chown -R root:root ${D}
}
