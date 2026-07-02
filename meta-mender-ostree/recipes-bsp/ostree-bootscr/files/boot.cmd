# U-Boot boot script for the Mender + OSTree demo on qemuarm64.
#
# Compiled to boot.scr.uimg by the ostree-bootscr recipe and placed on the FAT
# boot partition (vda1) via IMAGE_BOOT_FILES; U-Boot's distroboot scan runs it.
#
# OSTree owns the boot config on the sysroot (ext4, vda2): /boot/loader is a
# symlink OSTree swaps atomically between deployments, and /boot/loader/uEnv.txt
# provides kernel_image, ramdisk_image and bootargs (the latter carries the
# ostree= deployment path + ostree_root). We import it and boot that deployment,
# so a Mender/OSTree update that flips the deployment is picked up on next boot
# with no change to this static script.

echo "OSTree boot: scanning virtio"
virtio scan

# OSTree physical sysroot = ext4 partition 2 (vda2 => virtio 0:2). vda1 is FAT /boot.
setenv ostree_part 0:2

echo "OSTree boot: importing /boot/loader/uEnv.txt from virtio ${ostree_part}"
load virtio ${ostree_part} ${loadaddr} /boot/loader/uEnv.txt
env import -t ${loadaddr} ${filesize}

echo "OSTree boot: kernel=${kernel_image}"
echo "OSTree boot: bootargs=${bootargs}"

load virtio ${ostree_part} ${kernel_addr_r} ${kernel_image}
load virtio ${ostree_part} ${ramdisk_addr_r} ${ramdisk_image}

# ${filesize} is the ramdisk size from the load just above.
booti ${kernel_addr_r} ${ramdisk_addr_r}:${filesize} ${fdtcontroladdr}
