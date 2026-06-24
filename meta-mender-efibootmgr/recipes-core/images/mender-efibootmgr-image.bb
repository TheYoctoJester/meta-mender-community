SUMMARY = "Mender A/B demo image switched by UEFI boot entries (efibootmgr)"
DESCRIPTION = "Boots an EFI-stub kernel directly from the UEFI firmware. A/B \
slot selection is driven entirely through the UEFI boot manager: BootNext for \
the one-shot trial boot, BootOrder for the committed default. A custom \
efibootmgr-rootfs Mender Update Module performs the install/commit/rollback."
LICENSE = "MIT"

inherit core-image mender-efibootmgr

IMAGE_LINGUAS = " "

# Mender client, the efibootmgr toolchain the Update Module and the first-boot
# service rely on, and the kernel in the rootfs (the Update Module copies the
# new slot's /boot/bzImage onto the ESP).
IMAGE_INSTALL = " \
    packagegroup-core-boot \
    ${CORE_IMAGE_EXTRA_INSTALL} \
    mender-auth \
    mender-update \
    mender-configure \
    mender-connect \
    mender-update-module-efibootmgr \
    mender-data-persist \
    efibootmgr \
    efivar \
    util-linux \
    util-linux-blkid \
    util-linux-lsblk \
    util-linux-findmnt \
    e2fsprogs \
    dosfstools \
    coreutils \
    bash \
    kernel-image \
"

IMAGE_INSTALL:remove = "packagegroup-core-device-devel"

# Three copies of the EFI-stub kernel land on the ESP via bootimg-partition.
IMAGE_BOOT_FILES = " \
    bzImage;EFI/BOOT/bootx64.efi \
    bzImage;EFI/mender-a/bzImage.efi \
    bzImage;EFI/mender-b/bzImage.efi \
"

# Persistent Mender state lives on the data partition (see mender-data-persist
# in meta-mender-demos-common).
MENDER_DATA_PART = "/dev/disk/by-partlabel/data"

IMAGE_OVERHEAD_FACTOR = "1.3"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

# mender-image is disabled here, so its fstab generator does not run. Write the
# ESP and data mount lines ourselves, by partition label, so they are stable
# across the A/B rootfs swap. The root filesystem itself is mounted by the
# kernel from root=PARTUUID, so it needs no fstab entry.
ROOTFS_POSTPROCESS_COMMAND += "mender_efibootmgr_fstab; mender_efibootmgr_seed_data; mender_efibootmgr_bootstrap_artifact; "

# mender-update seeds its initial provides (artifact_name, device_type) from a
# bootstrap Artifact, normally installed by the mender-image dataimg/datatar
# flow we disabled. Generate one into /data/mender/bootstrap.mender (which the
# wic data partition is populated from, and which is bind-mounted to
# /var/lib/mender at runtime) so the device reports its artifact_name.
do_rootfs[depends] += "mender-artifact-native:do_populate_sysroot"

mender_efibootmgr_bootstrap_artifact() {
    install -d ${IMAGE_ROOTFS}/data/mender
    local devargs=""
    for dev in ${MENDER_DEVICE_TYPES_COMPATIBLE}; do
        devargs="${devargs} -c ${dev}"
    done
    mender-artifact write bootstrap-artifact \
        --artifact-name "${MENDER_ARTIFACT_NAME}" \
        ${devargs} \
        --output-path ${IMAGE_ROOTFS}/data/mender/bootstrap.mender
}

mender_efibootmgr_fstab() {
    local fstab="${IMAGE_ROOTFS}${sysconfdir}/fstab"
    install -d ${IMAGE_ROOTFS}/boot/efi
    install -d ${IMAGE_ROOTFS}/data
    sed -i '\#[[:space:]]/boot/efi[[:space:]]#d;\#[[:space:]]/data[[:space:]]#d' "$fstab" 2>/dev/null || true
    printf '/dev/disk/by-partlabel/ESP\t/boot/efi\tvfat\tdefaults\t0\t2\n' >> "$fstab"
    printf '/dev/disk/by-partlabel/data\t/data\text4\tdefaults\t0\t2\n' >> "$fstab"
}

# Seed the persistent /data/mender tree at build time. var-lib-mender.mount
# bind-mounts /data/mender over /var/lib/mender, which hides the rootfs copy of
# device_type / mender.conf that meta-mender installs there. Copy them onto the
# data tree (which the wic data partition is populated from) so the running
# client can read them. (We can't rely on the data recipe's first-boot tmpfiles
# copy, because the bootstrap artifact below makes /data/mender already exist.)
mender_efibootmgr_seed_data() {
    install -d -m 0700 ${IMAGE_ROOTFS}/data/mender
    if [ -d ${IMAGE_ROOTFS}${localstatedir}/lib/mender ]; then
        cp -a ${IMAGE_ROOTFS}${localstatedir}/lib/mender/. ${IMAGE_ROOTFS}/data/mender/
    fi
    install -d ${IMAGE_ROOTFS}/data/mender-configure
    echo "Mender efibootmgr A/B demo - persistent data" > ${IMAGE_ROOTFS}/data/demo.txt
}
