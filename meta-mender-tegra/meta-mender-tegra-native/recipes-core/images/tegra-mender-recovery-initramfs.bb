SUMMARY = "RAM-only Mender recovery system for the Tegra recovery partition"
DESCRIPTION = "A minimal system that runs entirely from RAM, so that neither rootfs \
A/B slot is mounted and both can be rewritten. It mounts the Mender data partition, \
so it authenticates to the server as the same device, and runs the Mender client in \
managed mode with the recovery-aware tegra-rootfs-image update module."
LICENSE = "Apache-2.0"

# Anything extra a product wants in its recovery system.
TEGRA_MENDER_RECOVERY_INSTALL ??= ""

# The network driver. A recovery system that cannot reach the server is only
# half a recovery system, so this is not optional in practice.
#
# It has to be named explicitly. meta-tegra lists the Realtek driver in
# MACHINE_EXTRA_RRECOMMENDS (orin-nx.inc, orin-nano.inc), but only
# packagegroup-base consumes that variable, and this image does not pull in
# packagegroup-base. The listed name kernel-module-r8168 is an RPROVIDES, which
# does not resolve in PACKAGE_INSTALL unless the providing recipe is built, so
# name the real package.
#
# Boards with a different NIC must override this.
TEGRA_MENDER_RECOVERY_NETDRV ?= "nv-kernel-module-r8168"

PACKAGE_INSTALL = "\
    tegra-mender-recovery-init \
    busybox \
    busybox-udhcpc \
    base-passwd \
    dropbear \
    ${ROOTFS_BOOTSTRAP_INSTALL} \
    ${TEGRA_MENDER_RECOVERY_INSTALL} \
    ${TEGRA_MENDER_RECOVERY_NETDRV} \
    e2fsprogs \
    e2fsprogs-e2fsck \
    e2fsprogs-dumpe2fs \
    e2fsprogs-resize2fs \
    tar \
    gzip \
    ca-certificates \
    chrony \
    dbus \
    mender-update \
    mender-auth \
    mender-flash \
    tegra-rootfs-update-module \
    tegra-redundant-boot-base \
    setup-nv-boot-control \
    tegra-firmware-xusb \
    kernel-module-nvme \
    kernel-module-pcie-tegra194 \
    kernel-module-phy-tegra194-p2u \
    kernel-module-dummy \
    kernel-module-uas \
    kernel-module-tegra-bpmp-thermal \
    kernel-module-pwm-tegra \
    kernel-module-pwm-fan \
"

# Weight the recovery system cannot afford in an 80 MiB partition, and does not
# use:
#   tegra-uefi-capsules  ~11 MB of capsule. The update module takes its capsule
#                        out of the artifact payload, never from disk. Only the
#                        legacy switch-rootfs state script reads the installed
#                        copy, and that scheme is not in play here.
#   jq                   a convenience for the stock rootfs-image module's
#                        config parsing. The Tegra-native module does not use it.
# ca-certificates is deliberately NOT dropped: without it the client cannot
# establish TLS to the server, which is the entire point of this image.
BAD_RECOMMENDATIONS = "tegra-uefi-capsules jq"

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""

COPY_LIC_MANIFEST = "0"
COPY_LIC_DIRS = "0"

COMPATIBLE_MACHINE = "(tegra)"

IMAGE_ROOTFS_SIZE = "32768"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_NAME_SUFFIX = ""

FORCE_RO_REMOVE ?= "1"

inherit core-image

# forcevariable, because a Mender distro inherits the Mender and tegraflash
# image classes globally and they append .ext4, .mender and .tegraflash-tar to
# IMAGE_FSTYPES. This is a ramdisk; none of those mean anything for it, and
# building them wastes a great deal of time. meta-tegra uses the same trick in
# tegra-espimage.bb.
IMAGE_FSTYPES:forcevariable = "cpio.gz"

# Inherited from a full image and meaningless for a ramdisk that is assembled
# once and never booted read-write.
IMAGE_POSTPROCESS_COMMAND = ""

# Note on tegra-rootfs-verify: it arrives with tegra-rootfs-update-module, which
# this image needs for the update module itself, so the verifier script and its
# unit are present here too. There is no systemd to run the unit, and the script
# refuses to run when it sees the recovery marker, because verifying from here
# would mark the boot chain's slot good and undo the exhausted retry counts that
# are usually the reason for being in recovery at all.

inherit nopackages
