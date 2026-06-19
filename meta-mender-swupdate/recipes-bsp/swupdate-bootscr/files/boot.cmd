# U-Boot boot script: select the active A/B rootfs slot for the
# Mender + SWUpdate demo on qemuarm64.
#
# Compiled into boot.scr.uimg by the swupdate-bootscr recipe and placed in
# the FAT boot partition (vda1) via IMAGE_BOOT_FILES; U-Boot's distroboot
# scan finds and runs it.
#
# SWUpdate writes the new rootfs to the inactive slot and sets the U-Boot
# env variable "rootpart" (2 = slot A /dev/vda2, 3 = slot B /dev/vda3) via
# its bootloader handler. We read it here and boot that slot. The kernel
# Image lives inside each rootfs at /boot/Image.

echo "SWUpdate A/B boot: initialising virtio"
virtio scan

if env exists rootpart; then
    echo "SWUpdate A/B boot: rootpart=${rootpart}"
else
    setenv rootpart 2
    saveenv
    echo "SWUpdate A/B boot: rootpart unset, defaulting to ${rootpart}"
fi

setenv bootargs "root=/dev/vda${rootpart} rootwait console=ttyAMA0,115200"
echo "SWUpdate A/B boot: bootargs=${bootargs}"

load virtio 0:${rootpart} ${kernel_addr_r} /boot/Image
booti ${kernel_addr_r} - ${fdtcontroladdr}
