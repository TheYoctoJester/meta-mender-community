FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Mender + barebox integration. See meta-mender-barebox/conf/layer.conf and the
# README for the design. The OS side is plain meta-mender + libubootenv; this
# bbappend is the bootloader half.

SRC_URI += " \
    file://mender.cfg \
    file://env/init/mender \
    file://env/boot/mender \
    file://dts/mender-bootenv.dtso \
"

# dtc compiles the uboot-environment overlay (dtso -> dtbo) into the built-in
# environment; /env/init/mender applies it to the live tree at startup.
DEPENDS += "dtc-native"

# Per-machine defconfig. oe-core's barebox.bbclass already maps qemuarm64 ->
# multi_v8_defconfig; set the RPi4 (aarch64) defconfig explicitly. Confirm the
# exact in-tree name against the barebox version oe-core pins (rpi_v8a_defconfig
# per upstream docs) at first build.
BAREBOX_CONFIG:raspberrypi4-64 ?= "rpi_v8a_defconfig"

# Disk base used to address the GPT-named rootfs slots from /env/boot/mender
# (/dev/<disk>.<partlabel>) and the boot args tail. Override per machine in the
# kas wrapper; these defaults are the expected barebox device names and MUST be
# confirmed on the first interactive boot (`barebox$ ls /dev/`).
BAREBOX_MENDER_DISK ?= "mmc1"
BAREBOX_MENDER_DISK:qemuarm64 ?= "virtioblk0"
BAREBOX_MENDER_DISK:raspberrypi4-64 ?= "disk0"

# Kernel image + device-tree file names inside each rootfs slot's /boot, and the
# kernel command-line tail shared by both slots.
BAREBOX_MENDER_KERNEL_IMAGE ?= "Image"
BAREBOX_MENDER_DTB_NAME ?= "${@d.getVar('KERNEL_DEVICETREE').split()[0].split('/')[-1] if d.getVar('KERNEL_DEVICETREE') else 'oftree'}"
BAREBOX_MENDER_BOOTARGS ?= "rootwait rw console=ttyS0,115200"
# qemu -M virt aarch64 uses the PL011 UART (ttyAMA0), not ttyS0.
BAREBOX_MENDER_BOOTARGS:qemuarm64 ?= "rootwait rw console=ttyAMA0,115200"
BAREBOX_MENDER_BOOTARGS:raspberrypi4-64 ?= "rootwait rw console=serial0,115200"

# Device-tree source for /env/boot/mender: "rootfs" (the slot's /boot dtb) or
# "internal" (barebox' own tree). Raspberry Pi must use "internal" so the kernel
# gets the VideoCore firmware tree (correct UART pin mux + barebox' mini-UART
# console), like a normal RPi boot.
BAREBOX_MENDER_DTB_SOURCE ?= "rootfs"
BAREBOX_MENDER_DTB_SOURCE:raspberrypi4-64 ?= "internal"

# Overlay barebox' built-in environment with the Mender boot scripts. The token
# substitution bakes the per-machine disk/kernel/dtb/bootargs into the scripts;
# barebox.bbclass passes BAREBOX_ENV_DIR to the build as an additional default
# environment path.
BAREBOX_ENV_DIR = "${WORKDIR}/mender-env"

do_configure:prepend() {
    install -d ${WORKDIR}/mender-env/init ${WORKDIR}/mender-env/boot ${WORKDIR}/mender-env/data
    sed -e 's|@BAREBOX_DISK@|${BAREBOX_MENDER_DISK}|g' \
        -e 's|@KERNEL_IMAGE@|${BAREBOX_MENDER_KERNEL_IMAGE}|g' \
        -e 's|@DTB_NAME@|${BAREBOX_MENDER_DTB_NAME}|g' \
        -e 's|@DTB_SOURCE@|${BAREBOX_MENDER_DTB_SOURCE}|g' \
        -e 's|@BOOTARGS@|${BAREBOX_MENDER_BOOTARGS}|g' \
        ${UNPACKDIR}/env/boot/mender > ${WORKDIR}/mender-env/boot/mender
    install -m 0644 ${UNPACKDIR}/env/init/mender ${WORKDIR}/mender-env/init/mender

    # Compile the uboot-environment overlay into the built-in environment. -@
    # emits the local fixups needed for the intra-overlay phandle.
    dtc -@ -I dts -O dtb \
        -o ${WORKDIR}/mender-env/data/mender-bootenv.dtbo \
        ${UNPACKDIR}/dts/mender-bootenv.dtso
}
