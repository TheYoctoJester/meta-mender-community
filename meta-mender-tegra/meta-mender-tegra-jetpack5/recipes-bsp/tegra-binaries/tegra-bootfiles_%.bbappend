
do_install:append() {
    cat <<EOF >${WORKDIR}/UDA.xml
<partition_layout>
    <device>
        <partition name="UDA">
            <filename> DATAFILE </filename>
        </partition>
    </device>
</partition_layout>
EOF

    nvflashxmlparse -v --rewrite-contents-from=${WORKDIR}/UDA.xml --output=${D}${datadir}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}.patched ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}
    mv ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}.patched ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}

    nvflashxmlparse -v --rewrite-contents-from=${WORKDIR}/UDA.xml --output=${D}${datadir}/tegraflash/${PARTITION_LAYOUT_EXTERNAL}.patched ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_EXTERNAL}
    mv ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_EXTERNAL}.patched ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_EXTERNAL}
}

do_install:append:tegra194() {
    # Remove invalid start locations from upstream L4T partition layout files that
    # prevents the Mender data partition to use remaining space.
    sed -i -e 's#<start_location> 0x708400000 </start_location>##g' \
           -e 's#<start_location> 0x710800000 </start_location>##g' \
		   ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}
    sed -i -e 's#<start_location> 0x708400000 </start_location>##g' \
           -e 's#<start_location> 0x710800000 </start_location>##g' \
		   ${D}${datadir}/tegraflash/${PARTITION_LAYOUT_EXTERNAL}
}