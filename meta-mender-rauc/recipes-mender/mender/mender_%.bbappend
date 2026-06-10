# RAUC owns the rootfs A/B update on this integration. The Mender client's stock
# "rootfs-image" Update Module would do its own partition writing (to
# MENDER_ROOTFS_PART_A/B) and directly conflicts, so drop just that module.
# The single-file and directory modules (generic file/app installers) and the
# rauc module are kept. FILES:mender-update packages the modules dir via a glob,
# so removing one file needs no FILES change.
do_install:append() {
    rm -f ${D}${datadir}/mender/modules/v3/rootfs-image
}
