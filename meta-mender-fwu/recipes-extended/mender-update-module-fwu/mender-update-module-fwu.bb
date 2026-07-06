SUMMARY = "Mender Update Module that drives U-Boot FWU Multi Bank Update for A/B switching"
DESCRIPTION = "Installs rootfs-image-fwu, a Mender Update Module that \
uses FWU v1 metadata as the bank-selection substrate instead of \
fw_setenv. Userspace metadata access goes through yafwumdata (from \
libfwumdata). The /etc/fwumdata.config file shipped here points \
yafwumdata at the FWU metadata GPT partitions."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://rootfs-image-fwu"

RDEPENDS:${PN} = " \
    bash \
    util-linux \
    util-linux-findmnt \
    coreutils \
    libfwumdata-bin \
    fwumdata-config \
    "

# All the boot-time plumbing that used to live in this recipe -- the
# /var/lib/mender mount, the device_type bootstrap, the eth0 DHCP
# stanza, the mender daemon startup -- now comes from meta-mender's
# canonical layout under systemd:
#
#   * mender-image MENDER_FEATURE -> /var/lib/mender symlinks to
#     /data/mender; mender's device_type / mender.conf ship into
#     /data/mender/.
#   * MENDER_DATA_PART = /dev/disk/by-partlabel/data -> mender-setup-
#     image.inc's fstab generator writes a correct /data mount line.
#   * wic file: `part /data --source rootfs --change-directory=data`
#     populates the data partition with the rootfs's /data tree at
#     wic time, so /data/mender/device_type arrives pre-seeded.
#   * SYSTEMD_AUTO_ENABLE in meta-mender's mender / mender-connect
#     recipes wires mender-authd.service / mender-updated.service /
#     mender-connect.service to multi-user.target.
#   * poky's systemd ships /usr/lib/systemd/network/80-wired.network
#     plus systemd-networkd enabled in PACKAGECONFIG, so eth0 DHCP
#     is automatic.
#
# This recipe therefore only ships the update module itself.

# v3 update modules live here for mender-update 5.x (same across the demos).
MENDER_MODULES_DIR = "${datadir}/mender/modules/v3"

do_install() {
    install -d "${D}${MENDER_MODULES_DIR}"
    install -m 0755 ${UNPACKDIR}/rootfs-image-fwu "${D}${MENDER_MODULES_DIR}/rootfs-image-fwu"
}

FILES:${PN} = "${MENDER_MODULES_DIR}/rootfs-image-fwu"
