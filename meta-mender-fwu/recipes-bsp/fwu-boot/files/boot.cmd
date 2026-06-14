# U-Boot boot script for FWU-aware Linux boot on qemuarm64-secureboot.
#
# Compiled by the fwu-bootscr recipe into boot.scr.uimg and placed in
# the ESP so U-Boot's distroboot / bootflow_script picks it up.
#
# All partition reads are RAW (no filesystem), so we use the
# "<interface> read" form rather than "load" which expects a file
# inside a filesystem. Partition offsets are looked up at runtime via
# "part start" so the script does not hard-code sector numbers.
#
# Partition table (matches qemuarm64-fwu.wks.in):
#   p1 esp                  p2 fwu-mdata-pri    p3 fwu-mdata-sec
#   p4 bank0-kernel         p5 bank0-rootfs
#   p6 bank1-kernel         p7 bank1-rootfs
#   p8 data

echo "FWU boot: scanning virtio"
virtio scan
virtio dev 0

# Ensure an EFI BootOrder entry exists so U-Boot's capsule-on-disk
# scan can find the ESP on the NEXT boot. The scan runs during U-Boot
# init before this script does, so on a truly fresh wic the entry we
# create here only takes effect once mender drops the capsule and
# reboots -- but by then ubootefi.var has been persisted to the ESP
# and the capsule scan sees a populated BootOrder. The `|| true`
# guards keep the script alive if entry 0001 already exists.
echo "FWU boot: ensuring EFI BootOrder is provisioned"
efidebug boot add -b 0001 fwu-test virtio 0:1 /boot.scr.uimg || true
efidebug boot order 0001 || true

echo "FWU boot: reading FWU metadata partition"
part start virtio 0 2 mdata_start
if test -n "${mdata_start}"; then
    virtio read ${loadaddr} ${mdata_start} 1
    setexpr active_addr ${loadaddr} + 0x8
    setexpr active_index *${active_addr}
else
    echo "FWU boot: part start failed; defaulting to bank 0"
    setenv active_index 0
fi
echo "FWU boot: active_index = ${active_index}"

# Default to bank 0
setenv kernel_part 4
setenv rootfs_uuid 10000000-0000-0000-0000-000000000002

# active_index may serialize as "1", "0x1", or "0x00000001"
if test "${active_index}" = "1"; then
    setenv kernel_part 6
    setenv rootfs_uuid 10000000-0000-0000-0000-000000000012
fi
if test "${active_index}" = "0x1"; then
    setenv kernel_part 6
    setenv rootfs_uuid 10000000-0000-0000-0000-000000000012
fi
if test "${active_index}" = "0x00000001"; then
    setenv kernel_part 6
    setenv rootfs_uuid 10000000-0000-0000-0000-000000000012
fi

echo "FWU boot: loading kernel from partition ${kernel_part}"
part start virtio 0 ${kernel_part} kstart
part size  virtio 0 ${kernel_part} ksize
echo "FWU boot: kernel partition starts at sector ${kstart}, size ${ksize}"
virtio read ${kernel_addr_r} ${kstart} ${ksize}

setenv bootargs "root=PARTUUID=${rootfs_uuid} rootwait console=ttyAMA0,115200 earlycon"
echo "FWU boot: bootargs=${bootargs}"

# Boot via the EFI stub so Linux gets a UEFI system table and the
# kernel-side efivarfs ends up populated. Without this Linux comes up
# with "efi: UEFI not found", and userspace tools (efibootmgr, efivar,
# writing /sys/firmware/efi/efivars/) have nothing to talk to -- which
# blocks any "set OsIndications and reboot" capsule trigger flow from
# the running OS.
#
# The "addr:size" form tells bootefi the binary size up-front. Without
# it U-Boot 2025.04 calls efi_get_image_parameters() to look up an
# image previously loaded through its own EFI loader and bails out with
# "No UEFI binary known at <addr>" -- our virtio-read placed the image
# in RAM but did not go through the EFI loader path, so the size must
# be supplied here.
setexpr ksize_bytes ${ksize} * 0x200
bootefi ${kernel_addr_r}:${ksize_bytes} ${fdtcontroladdr}
