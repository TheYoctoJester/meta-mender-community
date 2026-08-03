SUMMARY = "Init and tooling for the Tegra Mender recovery system"
DESCRIPTION = "The /init for the RAM-only recovery system that lives in the Tegra \
`recovery` partition, plus tegra-recovery, the manual fallback for repairing a \
rootfs slot when the Mender client cannot run."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "\
    file://recovery-init.sh \
    file://tegra-recovery \
    file://mender-recovery-start-client \
    file://recovery-reboot \
"

S = "${UNPACKDIR}"

COMPATIBLE_MACHINE = "(tegra)"
PACKAGE_ARCH = "${MACHINE_ARCH}"

# Informational only, so keep it out of the task signature. Without the
# vardepsexclude every build would restamp this and rebuild the image.
RECOVERY_STAMP ??= "${DATETIME}"
RECOVERY_STAMP[vardepsexclude] += "DATETIME"


# Labels the Tegra layouts actually use for the Mender data partition. UDA is
# the stock one; permanet_user_storage (sic, NVIDIA's spelling) appears in the
# substituted external layout this layer ships for machines that need a
# growable data partition.
TEGRA_MENDER_DATA_PARTLABELS ?= "UDA permanet_user_storage"

# NTP servers the recovery system tries once, with chronyd -q, after the network
# is up. Set empty to skip it entirely; the clock then falls back to the lower
# bound taken from the data partition's timestamps. A device on a closed network
# should point this at whatever it can actually reach.
TEGRA_MENDER_RECOVERY_NTP_SERVERS ?= "pool.ntp.org"

# Remote console in the recovery system: sshd with a blank root password.
#
# On by default, because a device that has lost both rootfs slots has no other
# way in except a serial cable, and avoiding the need for physical access is the
# entire point. It is still passwordless root over the network on a system that
# can rewrite both slots, so set this to "0" where that trade is wrong. The
# Mender client is unaffected either way: a device can still be repaired by a
# deployment, just not driven by hand.
TEGRA_MENDER_RECOVERY_SSH ?= "1"

do_install() {
    install -m 0755 ${UNPACKDIR}/recovery-init.sh ${D}/init
    sed -i -e "s#@@RECOVERY_STAMP@@#${RECOVERY_STAMP}#g" \
           -e "s#@@MENDER_DATA_PART@@#${MENDER_DATA_PART}#g" \
           -e "s#@@MENDER_DATA_PARTLABELS@@#${TEGRA_MENDER_DATA_PARTLABELS}#g" \
           -e "s#@@NTP_SERVERS@@#${TEGRA_MENDER_RECOVERY_NTP_SERVERS}#g" \
           -e "s#@@RECOVERY_SSH@@#${TEGRA_MENDER_RECOVERY_SSH}#g" \
           ${D}/init

    install -m 0555 -d ${D}/proc ${D}/sys
    # Deliberately no /var/log here: it lands in /var/volatile, which the
    # empty-dirs QA check rejects. The init creates it at runtime.
    install -m 0755 -d ${D}/dev ${D}/mnt ${D}/run ${D}/usr ${D}/data ${D}/boot/efi
    install -m 1777 -d ${D}/tmp
    mknod -m 622 ${D}/dev/console c 5 1

    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/tegra-recovery ${D}${bindir}/tegra-recovery
    install -m 0755 ${UNPACKDIR}/mender-recovery-start-client ${D}${bindir}/mender-recovery-start-client

    # Shadows busybox reboot for anything that inherits the init's PATH,
    # notably mender-update. See the comment in the script.
    install -d ${D}/usr/local/sbin
    install -m 0755 ${UNPACKDIR}/recovery-reboot ${D}/usr/local/sbin/reboot

    # The marker the update module keys off. Its presence, and nothing else, is
    # what puts the module into its recovery context, so it must ship only here
    # and never in a rootfs image.
    install -d ${D}${sysconfdir}
    echo "This system is the Tegra Mender recovery system." > ${D}${sysconfdir}/tegra-mender-recovery
    echo "tegra-rootfs-image reads this file to select its recovery context." >> ${D}${sysconfdir}/tegra-mender-recovery
}
do_install[vardepsexclude] += "DATETIME"

RDEPENDS:${PN} = "\
    util-linux-blkid \
    util-linux-lsblk \
    kmod \
    e2fsprogs-e2fsck \
    e2fsprogs-dumpe2fs \
    tegra-redundant-boot-base \
"

FILES:${PN} = "/"
