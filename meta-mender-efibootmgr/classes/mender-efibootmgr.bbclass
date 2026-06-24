# Mender A/B via UEFI boot entries (efibootmgr).
#
# This demonstrates an A/B integration that uses the UEFI boot manager itself
# as the slot selector: the firmware boots an EFI-stub kernel directly, a
# custom 'efibootmgr-rootfs' Update Module sets BootNext for the trial boot and
# rewrites BootOrder on commit. There is therefore NO stock Mender bootloader
# integration (no mender-grub / mender-uboot env), and the standard dynamic
# image/partition generation is replaced by an explicit WKS file -- the same
# approach as meta-mender-explicit-wic, but tailored to this boot chain.
#
# Mender state persistence is handled by the mender-data-persist recipe
# (bind-mount of /data/mender over /var/lib/mender), because disabling
# mender-image removes meta-mender's usual /var/lib/mender relocation.

inherit mender-setup mender-systemd

# Enable only the essentials: the client and systemd integration. No bootloader
# feature -- the Update Module owns A/B switching via efibootmgr. These are also
# set globally in the kas wrapper's local.conf so non-image recipes (mender,
# mender-connect, ...) observe the same feature set.
MENDER_FEATURES_ENABLE:append = " \
    mender-auth-install \
    mender-update-install \
    mender-systemd \
"

# Disable dynamic image generation and every stock bootloader integration. The
# fixed-size explicit WKS layout means growfs-data is not used either.
MENDER_FEATURES_DISABLE:append = " \
    mender-image \
    mender-part-images \
    mender-uboot \
    mender-grub \
    mender-bios \
    mender-growfs-data \
"

# Explicit WKS layout instead of dynamic generation.
WKS_FILE = "mender-efibootmgr-${MACHINE}.wks.in"
WKS_SEARCH_PATH:prepend = "${LAYERDIR_meta-mender-efibootmgr}/files/wic:"

# ext4 feeds the wic rootfs source and the out-of-band .mender artifact
# (see make-artifact.sh); wic is the bootable disk image.
IMAGE_FSTYPES:append = " ext4 wic wic.bz2"
IMAGE_FSTYPES:remove = " bootimg dataimg sdimg"
IMAGE_TYPEDEP:wic += "ext4"

ARTIFACTIMG_FSTYPE ?= "ext4"
