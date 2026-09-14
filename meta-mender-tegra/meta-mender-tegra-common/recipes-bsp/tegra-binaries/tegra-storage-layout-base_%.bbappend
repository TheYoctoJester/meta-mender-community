DEPENDS:append = " tegra-helper-scripts-native"
PATH =. "${STAGING_BINDIR_NATIVE}/tegra-flash:"

# Which partition the mender data image goes on.
#
# The default is permanet_user_storage, a partition NVIDIA's layouts do not have
# and which do_install appends after APP_b, marked fill-to-end so it takes the
# rest of the device. UDA, the obvious candidate, is not ours to use: NVIDIA
# state it is "reserved by NV for OTA process", and a layout that moves it to the
# end so it could grow is what fails in
# https://forums.developer.nvidia.com/t/jetson-orin-nx-custom-partition-layout-fails-with-uda-at-the-end/316401/6
#
# Set this to UDA to keep the old arrangement, which is what every machine except
# p3768-0000-p3767-0000 had before. Existing fleets need that, because the
# partition number lands in /etc/fstab: a device flashed with its data on UDA
# that takes a rootfs update built for the trailing partition would mount a
# partition that is not there. Moving a fleet across needs a reflash, not an
# update. Set MENDER_DATA_PART_NUMBER to match, or the check below fails the
# build.
#
# Nothing is appended when the named partition is already in the layout, so UDA
# selects the stock arrangement untouched.
#
# Declared in tegra-mender-common.bbclass, not here: the image recipes need it
# too, since the partition number derived from it lands in /etc/fstab.

# The size written into that partition's <size> in the staged layout.
#
# TEGRA_MENDER_UDA_SIZE_MB came in with the fix that first carried
# MENDER_DATA_PART_SIZE_MB into the layout, and was named after UDA because that
# is where the data image went then. The partition is selectable now, so the
# variable is named for its job instead and the old name feeds it: a
# configuration written against the old name keeps working unchanged, including
# setting it empty to skip the size rewrite and leave the layout's own size
# alone.
#
# On the default arrangement the size is only a floor, since the partition is
# appended fill-to-end and grows past it. It is load-bearing on the UDA path,
# where the partition is fixed-size and an oversized data image does not fit.
TEGRA_MENDER_UDA_SIZE_MB ?= "${@d.getVar('MENDER_DATA_PART_SIZE_MB') or ''}"
TEGRA_MENDER_DATA_PART_SIZE_MB ?= "${TEGRA_MENDER_UDA_SIZE_MB}"

def mender_layout_partition_numbers(path):
    """What nvflashxmlparse will number each partition in this layout.

    Explicit ids win and the rest follow on from the previous one, with the
    partition-table entries not counting. Note that document order is not id
    order: these layouts declare APP last as id 1, so a running counter ends low
    and the next free number is one past the highest assigned, not one past the
    last seen.
    """
    import xml.etree.ElementTree as ET
    table = ("protective_master_boot_record", "primary_gpt", "secondary_gpt")
    out = {}
    for dev in ET.parse(path).getroot().findall("device"):
        nxt = 1
        for part in dev.findall("partition"):
            if part.get("type") in table:
                continue
            pid = part.get("id")
            num = int(pid) if pid else nxt
            nxt = num + 1
            out.setdefault(dev.get("type"), {})[part.get("name")] = num
    return out

def mender_layout_files(d):
    """The staged layouts that might carry user partitions, as (name, path)."""
    import os
    layoutdir = os.path.join(d.getVar("D") + d.getVar("datadir"), "l4t-storage-layout")
    found = []
    for var in ("PARTITION_LAYOUT_TEMPLATE", "PARTITION_LAYOUT_EXTERNAL"):
        fname = d.getVar(var)
        if not fname:
            continue
        path = os.path.join(layoutdir, fname)
        if os.path.exists(path):
            found.append((fname, path))
    return found

python mender_flash_layout_add_data_partition() {
    import re

    # Fill-to-end (0x808) is what makes the partition worth having; the declared
    # size is only a floor. No <filename> here, that is the rewrite's job.
    BLOCK = '''        <partition name="%s" id= "%d" type="data">
            <allocation_policy> sequential </allocation_policy>
            <filesystem_type> basic </filesystem_type>
            <size> %d </size>
            <file_system_attribute> 0 </file_system_attribute>
            <allocation_attribute> 0x808 </allocation_attribute>
            <percent_reserved> 0 </percent_reserved>
            <align_boundary> 16384 </align_boundary>
            <description> **Required.** This partition stores permanent user and
              device data across A/B updates</description>
        </partition>
'''

    name = d.getVar("TEGRA_MENDER_DATA_PART_NAME")
    if not name:
        bb.fatal("TEGRA_MENDER_DATA_PART_NAME is empty, so nothing would carry the data image")
    # Falls back when the size rewrite is switched off: the partition still has to
    # declare something, and fill-to-end makes the floor immaterial anyway.
    size_mb = d.getVar("TEGRA_MENDER_DATA_PART_SIZE_MB") or d.getVar("MENDER_DATA_PART_SIZE_MB")
    size = int(size_mb) * 1024 * 1024

    for fname, path in mender_layout_files(d):
        text = open(path).read()
        if 'name="%s"' % name in text:
            bb.note("%s: %s already present, layout left alone" % (fname, name))
            continue

        # No rootfs slots means this layout carries no user data, such as the
        # QSPI-only internal one on a board that boots from a drive.
        m = re.search(r'<partition name="APP_b".*?</partition>\s*\n', text, re.S)
        if not m:
            continue

        if name == "UDA":
            bb.fatal("%s has no UDA partition and creating one is not safe, since NVIDIA "
                     "reserve UDA for their own OTA process. Leave "
                     "TEGRA_MENDER_DATA_PART_NAME at its default." % fname)

        # Numbering is per device, and these layouts describe more than one: the
        # SD template carries a 60-partition spi device next to the 16-partition
        # sdcard. Take the highest id from the device the rootfs slots are in,
        # not from the file, or the card ends up asking for partition 61.
        numbers = mender_layout_partition_numbers(path)
        target = next((dev for dev, parts in numbers.items() if "APP_b" in parts), None)
        if target is None:
            bb.fatal("%s: found an APP_b partition in the text but not in the parsed "
                     "layout, which should be impossible" % fname)
        nextid = max(numbers[target].values()) + 1
        with open(path, "w") as f:
            f.write(text[:m.end()] + BLOCK % (name, nextid, size) + text[m.end():])
        bb.note("%s: appended %s as partition %d" % (fname, name, nextid))
}

python mender_flash_layout_check_part_number() {
    name = d.getVar("TEGRA_MENDER_DATA_PART_NAME")
    want = d.getVar("MENDER_DATA_PART_NUMBER")
    if not want:
        return
    seen = False
    for fname, path in mender_layout_files(d):
        for devtype, parts in mender_layout_partition_numbers(path).items():
            if name not in parts:
                continue
            seen = True
            got = parts[name]
            if str(got) != str(want):
                bb.fatal("%s (%s): %s is partition %d, but MENDER_DATA_PART_NUMBER says %s. "
                         "The rootfs would mount the wrong device, or none at all. Fix "
                         "MENDER_DATA_PART_NUMBER_DEFAULT for this machine in "
                         "tegra-mender-common.bbclass." % (fname, devtype, name, got, want))
            bb.note("%s (%s): %s is partition %d, matching MENDER_DATA_PART_NUMBER"
                    % (fname, devtype, name, got))
    if not seen:
        bb.fatal("no staged layout contains a partition named %s, so the data image has "
                 "nowhere to go. Check TEGRA_MENDER_DATA_PART_NAME." % name)
}

mender_flash_layout_write_filename_map() {
    cat <<EOF >$1
<partition_layout>
    <device>
        <partition name="${TEGRA_MENDER_DATA_PART_NAME}">
            <filename> DATAFILE </filename>
        </partition>
    </device>
</partition_layout>
EOF
}

mender_flash_layout_write_size_map() {
    rm -f $1
    [ -n "${TEGRA_MENDER_DATA_PART_SIZE_MB}" ] || return 0
    cat <<EOF >$1
<partition_layout>
    <device>
        <partition name="${TEGRA_MENDER_DATA_PART_NAME}">
            <size> ${@int(d.getVar('TEGRA_MENDER_DATA_PART_SIZE_MB') or 0) * 1024 * 1024} </size>
        </partition>
    </device>
</partition_layout>
EOF
}

mender_flash_layout_adjust() {
    local file=$1
    [ -e ${D}${datadir}/l4t-storage-layout/$file ] || return 0
    mv ${D}${datadir}/l4t-storage-layout/$file ${WORKDIR}/$file
    nvflashxmlparse -v --rewrite-contents-from=${WORKDIR}/data-filename.xml \
		--output=${WORKDIR}/$file.contents \
		${WORKDIR}/$file
    if [ -s ${WORKDIR}/data-size.xml ]; then
        nvflashxmlparse -v --update-parttype-sizes-from=${WORKDIR}/data-size.xml:data \
		--output=${D}${datadir}/l4t-storage-layout/$file \
		${WORKDIR}/$file.contents
    else
        mv ${WORKDIR}/$file.contents ${D}${datadir}/l4t-storage-layout/$file
    fi
}

mender_flash_layout_rewrite() {
    mender_flash_layout_write_filename_map ${WORKDIR}/data-filename.xml
    mender_flash_layout_write_size_map ${WORKDIR}/data-size.xml

    mender_flash_layout_adjust "${PARTITION_LAYOUT_TEMPLATE}"
    mender_flash_layout_adjust "${PARTITION_LAYOUT_EXTERNAL}"
    chown -R root:root ${D}
}

# All three run after do_install, because do_install is what stages the layouts
# in the first place: a prefunc would find no files and silently do nothing. The
# order matters as well. The partition has to exist before its filename and size
# can be rewritten, and the number can only be checked once the layout is final.
do_install[postfuncs] += "mender_flash_layout_add_data_partition mender_flash_layout_rewrite mender_flash_layout_check_part_number"
