# mender-barebox-ab.bbclass
#
# Build-time half of the Mender + barebox A/B demo. Applied to the image recipe
# (core-image-minimal) by the kas wrapper via IMAGE_CLASSES.
#
# barebox owns slot selection at runtime (see /env/boot/mender), and Mender's
# stock rootfs-image module owns the A/B rootfs. mender-image / mender-part-
# images are disabled in this demo (the explicit wks owns the layout), so this
# class provides the image-side glue meta-mender would otherwise supply:
#
#   * the initial U-Boot-format environment, built with mkenvimage and deployed
#     for the wks to copy raw into the mender-bootenv partition. Both barebox'
#     ubootvar driver and libubootenv's fw_setenv/fw_printenv read this format;
#   * fstab lines (boot/firmware FAT -> /boot/firmware, data -> /data) by
#     partition label, so they are stable across the A/B rootfs swap. The root
#     is mounted by the kernel from root=PARTLABEL set by barebox, so it needs
#     no fstab entry;
#   * a seeded /data/mender tree (the data partition is populated from it) and a
#     bootstrap Artifact, so the device reports its artifact_name to the server.

# Size of the U-Boot env. Keep in lock-step with fw_env.config and the
# mender-bootenv partition size in the wks. ubootvar CRCs the WHOLE partition
# (read_file reads the full cdev), so env size MUST equal the partition size.
BAREBOX_MENDER_ENV_SIZE ?= "0x100000"

# Initial environment seeded into the env partition. Same variable names the
# Mender rootfs-image module reads/writes; bootlimit drives the rollback in
# /env/boot/mender. Slot A == partition 2.
BAREBOX_MENDER_ENV_SEED ?= "\
mender_boot_part=2\n\
mender_boot_part_hex=2\n\
upgrade_available=0\n\
bootcount=0\n\
bootlimit=1\n\
mender_check_saveenv_canary=1\n\
mender_saveenv_canary=1\n\
"

# mkenvimage (u-boot-tools-native) builds the env image; the wks rawcopy and the
# bootstrap artifact need their inputs in DEPLOY_DIR_IMAGE before wic runs.
do_image_wic[depends] += " u-boot-tools-native:do_populate_sysroot"

# wic stages the barebox image into the boot partition via IMAGE_BOOT_FILES, so
# it must wait for barebox to be deployed (otherwise wic can race a barebox
# recompile and find the image missing in DEPLOY_DIR_IMAGE).
do_image_wic[depends] += " virtual/bootloader:do_deploy"

python do_barebox_env_image() {
    import os, subprocess
    deploy = d.getVar('DEPLOY_DIR_IMAGE')
    size = d.getVar('BAREBOX_MENDER_ENV_SIZE')
    seed = d.getVar('BAREBOX_MENDER_ENV_SEED').replace('\\n', '\n')

    txt = os.path.join(deploy, 'mender-uboot-env.txt')
    img = os.path.join(deploy, 'mender-uboot-env.img')
    with open(txt, 'w') as f:
        f.write(seed)

    # Non-redundant U-Boot env: 4-byte CRC32 + NUL-separated KEY=VALUE pairs.
    subprocess.check_call(['mkenvimage', '-s', size, '-o', img, txt])
}
addtask do_barebox_env_image before do_image_wic after do_rootfs
do_barebox_env_image[dirs] = "${DEPLOY_DIR_IMAGE}"
do_barebox_env_image[depends] += " u-boot-tools-native:do_populate_sysroot"

do_rootfs[depends] += " mender-artifact-native:do_populate_sysroot"
ROOTFS_POSTPROCESS_COMMAND += "mender_barebox_fstab; mender_barebox_seed_data; mender_barebox_bootstrap_artifact; "

# Mount the FAT boot/firmware partition and the data partition by label so they
# are stable across the A/B swap. The rootfs is mounted by the kernel from
# root=PARTLABEL (set by barebox), so it needs no fstab entry.
mender_barebox_fstab() {
    local fstab="${IMAGE_ROOTFS}${sysconfdir}/fstab"
    install -d ${IMAGE_ROOTFS}/boot/firmware
    install -d ${IMAGE_ROOTFS}/data
    sed -i -E '\#[[:space:]]/boot/firmware[[:space:]]#d; \#[[:space:]]/data[[:space:]]#d' "$fstab" 2>/dev/null || true
    printf '/dev/disk/by-partlabel/mender-boot\t/boot/firmware\tvfat\tdefaults\t0\t2\n' >> "$fstab"
    printf '/dev/disk/by-partlabel/mender-data\t/data\text4\tdefaults\t0\t2\n' >> "$fstab"
}

# Seed the persistent /data/mender tree at build time. var-lib-mender.mount
# bind-mounts /data/mender over /var/lib/mender, which hides the rootfs copy of
# device_type / mender.conf that meta-mender installs there; copy them onto the
# data tree (which the wic data partition is populated from) so the running
# client can read them.
mender_barebox_seed_data() {
    install -d -m 0700 ${IMAGE_ROOTFS}/data/mender
    if [ -d ${IMAGE_ROOTFS}${localstatedir}/lib/mender ]; then
        cp -a ${IMAGE_ROOTFS}${localstatedir}/lib/mender/. ${IMAGE_ROOTFS}/data/mender/
    fi
    echo "Mender barebox A/B demo - persistent data" > ${IMAGE_ROOTFS}/data/demo.txt
}

# mender-update seeds its initial provides (artifact_name, device_type) from a
# bootstrap Artifact, normally installed by the mender-image flow we disabled.
mender_barebox_bootstrap_artifact() {
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
