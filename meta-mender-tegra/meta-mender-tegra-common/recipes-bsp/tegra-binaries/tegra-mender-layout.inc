# The flash-layout filename map, shared by the two storage-layout bbappends in
# this directory. include_single_file searches the including file's own directory
# before BBPATH, so a plain require works from either of them, and neither is
# reachable through BBFILES.
#
# Two variables, because the two layout sources are not equivalent:
#
#   TEGRA_MENDER_LAYOUT_FILENAMES        applied to the layouts staged by
#                                        tegra-storage-layout-base, which are
#                                        NVIDIA's. It names the data partition,
#                                        and which partition that is depends on
#                                        the layout, so it must not be applied to
#                                        a layout this layer supplies itself.
#   TEGRA_MENDER_LAYOUT_FILENAMES_EXTRA  applied to every layout, NVIDIA's and
#                                        ours alike. For entries that are correct
#                                        whatever the layout, which is what the
#                                        recovery boot image is: a partition
#                                        called recovery holds it or the layout
#                                        does not have one.
#
# Keeping them apart is not cosmetic. flash_l4t_t234_nvme_rootfs_ab.xml in this
# layer puts the data image on permanet_user_storage and deliberately leaves UDA
# without a filename, so feeding it "UDA:DATAFILE" would have the data image
# flashed to two partitions.
#
# nvflashxmlparse's rewrite walks the partitions of the *input* layout and looks
# each one up in the map, leaving anything it does not find alone. So one list
# covers both the internal and the external layout, and an entry naming a
# partition a given layout does not have costs nothing but a "No rewrite applied"
# line in the log. Neither field may contain a space or a colon.
TEGRA_MENDER_LAYOUT_FILENAMES ?= "UDA:DATAFILE"
TEGRA_MENDER_LAYOUT_FILENAMES_EXTRA ?= ""

# $1 = file to write the rewrite document to, $2... = "<partition>:<filename>" pairs
mender_flash_layout_write_map() {
    local map=$1
    shift
    echo '<partition_layout>' >$map
    echo '    <device>' >>$map
    for pair in "$@"; do
        echo "        <partition name=\"${pair%%:*}\">" >>$map
        echo "            <filename> ${pair#*:} </filename>" >>$map
        echo '        </partition>' >>$map
    done
    echo '    </device>' >>$map
    echo '</partition_layout>' >>$map
}
