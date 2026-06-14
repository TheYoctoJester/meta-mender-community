SUMMARY = "Minimal Yocto image to exercise U-Boot FWU Multi Bank Update on QEMU"
DESCRIPTION = "Boots on qemuarm64-secureboot. Carries the userspace tooling \
needed to construct UEFI capsules, drop them in the EFI System Partition, \
read FWU metadata, and inspect EFI variables."
LICENSE = "MIT"

inherit core-image

IMAGE_FEATURES += "ssh-server-openssh tools-debug"

# Tools needed to: build capsules (mkeficapsule lives in u-boot-tools),
# read/write EFI vars, see GPT partitions, look at FWU metadata,
# and provide a usable interactive shell.
IMAGE_INSTALL:append = " \
    u-boot-tools \
    efivar \
    efibootmgr \
    util-linux \
    util-linux-fdisk \
    util-linux-blkid \
    util-linux-lsblk \
    util-linux-findmnt \
    e2fsprogs \
    parted \
    dosfstools \
    coreutils \
    bash \
    libfwumdata \
    libfwumdata-bin \
    fwumdata-config \
    "

IMAGE_FSTYPES = "ext4 wic wic.qcow2 wic.bmap"

# Ensure ext4 is built before wic so the bank1-rootfs rawcopy finds it.
IMAGE_TYPEDEP:wic += "ext4"
IMAGE_TYPEDEP:wic.qcow2 += "ext4"

# Use our FWU-aware GPT layout, stage the initial FWU metadata before
# wic runs, ship the FWU-aware boot script into the ESP via bootimg-
# partition, and reduce IMAGE_BOOT_FILES to just boot.scr.uimg --
# U-Boot loads the kernel from the active bank's kernel partition,
# not from the ESP, so we don't need Image there.
WKS_FILE = "qemuarm64-fwu.wks.in"
IMAGE_BOOT_FILES = "boot.scr.uimg"
do_image_wic[depends] += " fwu-mdata-init:do_deploy fwu-bootscr:do_deploy"
