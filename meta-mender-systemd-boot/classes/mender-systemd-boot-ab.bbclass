# mender-systemd-boot-ab.bbclass
#
# Build-time half of the systemd-boot A/B demo. Applied to the image recipe
# (core-image-minimal) by the kas wrapper via IMAGE_CLASSES.
#
# It produces, for an unpatched systemd-boot using native Automatic Boot
# Assessment:
#
#   * two Type #1 Boot Loader Specification entries (mender-a.conf /
#     mender-b.conf), each naming that slot's kernel + initrd on the ESP and
#     carrying root=PARTLABEL=mender-rootfs{a,b} on the kernel command line;
#   * an initial loader.conf whose `default` selects slot A;
#   * per-slot copies of the kernel + initrd staged onto the ESP under
#     /EFI/Linux/mender-{a,b}/ (deployed by the bootimg_efi wic plugin via
#     IMAGE_EFI_BOOT_FILES);
#   * a copy of the kernel + initrd inside the rootfs at /usr/lib/mender/,
#     so a Mender rootfs artifact carries the kernel for the slot it lands
#     on (the shim copies it from the freshly-written inactive slot onto the
#     ESP at flip time);
#   * a placeholder that overwrites the boot.conf the bootimg_efi plugin
#     auto-generates for systemd-boot (an entry pointing at a kernel we do
#     not stage at the ESP root), so the menu only carries our two entries;
#   * fstab lines (ESP -> /boot, data -> /data), a seeded /data/mender tree
#     and a bootstrap artifact -- mender-image is disabled in this demo, so
#     none of meta-mender's image-side glue runs and we provide it here.

# Number of boot attempts the trial slot is armed with. systemd-boot
# decrements this at selection time; when it reaches zero the entry is
# "bad" and the firmware prefers the still-good committed slot -- that is
# the rollback. 1 == strict one-shot trial (matches Mender's single trial
# boot before commit).
MENDER_SDBOOT_BOOT_TRIES ?= "1"

# Kernel command line shared by both slots, minus the per-slot root=.
# panic=5 reboots a trial kernel that panics, so Automatic Boot Assessment
# gets a chance to count it out and fall back.
# systemd.gpt_auto=0 is essential: systemd-gpt-auto-generator would otherwise
# auto-mount the ESP (by GPT type) at /boot/efi in addition to our fstab /boot
# mount. Because the ESP is FAT (case-insensitive), that second mount shadows
# the /boot/EFI directory and the shim's kernel writes never reach the ESP
# root systemd-boot actually reads -- silently breaking the A/B slot flip.
MENDER_SDBOOT_APPEND ?= "rootwait rw console=ttyS0,115200 panic=5 systemd.gpt_auto=0"

# The deployed initramfs filename in DEPLOY_DIR_IMAGE. meta-mender names
# images after MENDER_DEVICE_TYPE (see IMAGE_LINK_NAME in mender-setup), not
# MACHINE, so the initramfs link name uses it too. INITRAMFS_FSTYPES is
# pinned to cpio.gz by the wrapper.
MENDER_SDBOOT_INITRD_NAME ?= "${INITRAMFS_IMAGE}-${MENDER_DEVICE_TYPE}.cpio.gz"

# Files the bootimg_efi plugin stages onto the ESP. The kernel/initrd
# sources are looked up in DEPLOY_DIR_IMAGE; the *.conf sources are written
# there by do_sdboot_esp_config below.
IMAGE_EFI_BOOT_FILES = "\
    ${KERNEL_IMAGETYPE};EFI/Linux/mender-a/bzImage \
    ${KERNEL_IMAGETYPE};EFI/Linux/mender-b/bzImage \
    ${MENDER_SDBOOT_INITRD_NAME};EFI/Linux/mender-a/initrd \
    ${MENDER_SDBOOT_INITRD_NAME};EFI/Linux/mender-b/initrd \
    sdboot-loader.conf;loader/loader.conf \
    sdboot-mender-a.conf;loader/entries/mender-a.conf \
    sdboot-mender-b.conf;loader/entries/mender-b.conf \
    sdboot-boot-noop.conf;loader/entries/boot.conf \
"

# Write the loader.conf, the two BLS entries and the boot.conf placeholder
# into DEPLOY_DIR_IMAGE so the bootimg_efi plugin can pick them up.
python do_sdboot_esp_config() {
    import os

    deploy = d.getVar('DEPLOY_DIR_IMAGE')
    append = d.getVar('MENDER_SDBOOT_APPEND')

    def write(name, content):
        with open(os.path.join(deploy, name), 'w') as f:
            f.write(content)

    # No explicit `default`: selection is driven by systemd's native
    # Automatic Boot Assessment. Among the entries, the one with the highest
    # `version` that is not "bad" (counted out) wins, so a counted-out trial
    # automatically yields to the still-good committed slot -- the rollback.
    # An explicit `default` would instead pin a slot even after it goes bad,
    # defeating the firmware rollback.
    write('sdboot-loader.conf', "timeout 5\n")

    # Slot A is the initial committed default: it is given the higher version
    # (1) so it sorts first at first boot; slot B is a build-time clone with
    # version 0. The shim assigns monotonically increasing versions on each
    # flip so the trial slot always outranks the committed one while good.
    for slot, part, version in (('a', 'mender-rootfsa', 1),
                                ('b', 'mender-rootfsb', 0)):
        write('sdboot-mender-%s.conf' % slot,
              "title Mender slot %s\n"
              "sort-key mender\n"
              "version %d\n"
              "linux /EFI/Linux/mender-%s/bzImage\n"
              "initrd /EFI/Linux/mender-%s/initrd\n"
              "options root=PARTLABEL=%s %s\n"
              % (slot.upper(), version, slot, slot, part, append))

    # Overwrite the bootimg_efi-generated boot.conf with a comment-only file;
    # systemd-boot ignores an entry that names no kernel.
    write('sdboot-boot-noop.conf',
          "# Intentionally empty: this demo uses mender-a.conf / mender-b.conf.\n")
}
addtask do_sdboot_esp_config before do_image_wic after do_rootfs
do_sdboot_esp_config[dirs] = "${DEPLOY_DIR_IMAGE}"

# wic needs the kernel, the initramfs and systemd-boot deployed before it
# assembles the ESP.
do_image_wic[depends] += " \
    virtual/kernel:do_deploy \
    ${INITRAMFS_IMAGE}:do_image_complete \
    systemd-boot:do_deploy \
"

# Stage the kernel + initrd into the rootfs and provide the image-side glue
# that mender-image would otherwise supply.
do_rootfs[depends] += " \
    virtual/kernel:do_deploy \
    ${INITRAMFS_IMAGE}:do_image_complete \
    mender-artifact-native:do_populate_sysroot \
"
ROOTFS_POSTPROCESS_COMMAND += "mender_sdboot_stage_kernel; mender_sdboot_fstab; mender_sdboot_seed_data; mender_sdboot_bootstrap_artifact; "

# Copy this build's kernel + initrd into /usr/lib/mender so the rootfs
# artifact carries them; the shim copies them onto the ESP for whichever
# slot the rootfs is written to.
mender_sdboot_stage_kernel() {
    install -d ${IMAGE_ROOTFS}/usr/lib/mender
    install -m 0644 ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE} \
        ${IMAGE_ROOTFS}/usr/lib/mender/bzImage
    install -m 0644 ${DEPLOY_DIR_IMAGE}/${MENDER_SDBOOT_INITRD_NAME} \
        ${IMAGE_ROOTFS}/usr/lib/mender/initrd
}

# mender-image is disabled, so write the ESP + data mounts ourselves, by
# partition label, so they are stable across the A/B rootfs swap. The root
# filesystem is mounted by the initramfs from root=PARTLABEL, so it needs no
# fstab entry.
mender_sdboot_fstab() {
    local fstab="${IMAGE_ROOTFS}${sysconfdir}/fstab"
    install -d ${IMAGE_ROOTFS}/boot/efi
    install -d ${IMAGE_ROOTFS}/data
    # Mount the ESP at /boot/efi (NOT /boot). The systemd stack on this
    # image insists on an ESP mount at /boot/efi; if we ALSO mount it at
    # /boot, the FAT ESP is mounted twice and -- because FAT is
    # case-insensitive -- the /boot/efi mount shadows the /boot/EFI
    # directory, so the shim's writes never reach the ESP root systemd-boot
    # reads, silently breaking the A/B slot flip. Mounting only at /boot/efi
    # (and pointing the shim there) keeps a single, unambiguous ESP mount.
    sed -i -E '\#[[:space:]]/boot(/efi)?[[:space:]]#d; \#[[:space:]]/data[[:space:]]#d' "$fstab" 2>/dev/null || true
    printf '/dev/disk/by-partlabel/ESP\t/boot/efi\tvfat\tdefaults\t0\t2\n' >> "$fstab"
    printf '/dev/disk/by-partlabel/mender-data\t/data\text4\tdefaults\t0\t2\n' >> "$fstab"
}

# Seed the persistent /data/mender tree at build time. var-lib-mender.mount
# bind-mounts /data/mender over /var/lib/mender, which hides the rootfs copy
# of device_type / mender.conf that meta-mender installs there. Copy them
# onto the data tree (which the wic data partition is populated from) so the
# running client can read them.
mender_sdboot_seed_data() {
    install -d -m 0700 ${IMAGE_ROOTFS}/data/mender
    if [ -d ${IMAGE_ROOTFS}${localstatedir}/lib/mender ]; then
        cp -a ${IMAGE_ROOTFS}${localstatedir}/lib/mender/. ${IMAGE_ROOTFS}/data/mender/
    fi
    echo "Mender systemd-boot A/B demo - persistent data" > ${IMAGE_ROOTFS}/data/demo.txt
}

# mender-update seeds its initial provides (artifact_name, device_type) from
# a bootstrap Artifact, normally installed by the mender-image flow we
# disabled. Generate one into /data/mender/bootstrap.mender so the device
# reports its artifact_name to the server.
mender_sdboot_bootstrap_artifact() {
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
