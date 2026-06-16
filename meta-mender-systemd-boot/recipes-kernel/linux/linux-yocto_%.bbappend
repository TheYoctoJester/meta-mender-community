# AHCI + ext4 + vfat + EFI stub built into the kernel for the systemd-boot
# A/B demo. Only applies to the demo machine; other machines are untouched.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:qemux86-64 = " file://mender-sdboot.cfg"
