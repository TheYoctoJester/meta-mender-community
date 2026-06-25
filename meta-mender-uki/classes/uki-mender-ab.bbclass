# uki-mender-ab.bbclass — produce two UKIs (slot A + slot B) and stage both
# into the image rootfs at /usr/lib/mender/ so a Mender rootfs artifact
# carries both kernels in lockstep with the rootfs.
#
# The parent class (uki) builds uki-a.efi (the "main" UKI). We then run
# ukify a second time to build uki-b.efi with a different cmdline pointing
# at the other rootfs partition.

# Slot A is the default. We override the upstream defaults from uki.bbclass
# so that the standard do_uki produces uki-a.efi pointing at rootfsa.
UKI_FILENAME = "uki-a.efi"
UKI_CMDLINE = "rootwait root=PARTLABEL=mender-rootfsa console=${KERNEL_CONSOLE}"

# Slot B
UKI_FILENAME_B ?= "uki-b.efi"
UKI_CMDLINE_B ?= "rootwait root=PARTLABEL=mender-rootfsb console=${KERNEL_CONSOLE}"

inherit uki

# Deploy ONLY the committed image at first boot: slot A's UKI as
# uki-current.efi, plus a loader.conf with NO `default`. mender-uki-shim
# drives A/B via systemd-boot boot counting and the sort order of the on-ESP
# filenames (a trial is staged as uki-update+N.efi, which sorts before
# uki-current.efi and is demoted past it once its counter hits zero), so an
# explicit `default` must NOT be set -- systemd-boot honours `default` without
# any bad-entry check and would keep booting an exhausted trial. The slot-B
# UKI is not placed on the ESP at build time; it travels in the rootfs
# (/usr/lib/mender) and the shim stages it on demand.
IMAGE_EFI_BOOT_FILES = "\
    ${UKI_FILENAME};EFI/Linux/uki-current.efi \
    loader.conf;loader/loader.conf \
"

# Build the slot-B UKI right after the (slot-A) standard do_uki, and stage
# both copies into ${IMAGE_ROOTFS}/usr/lib/mender/ so Mender artifacts
# carry the kernel.
python do_uki_b() {
    import os, shutil, bb.process

    ukify_cmd = d.getVar('UKIFY_CMD')
    deploy_dir_image = d.getVar('DEPLOY_DIR_IMAGE')

    target_arch = d.getVar('EFI_ARCH')
    if target_arch:
        ukify_cmd += " --efi-arch %s" % target_arch
    stub = "%s/linux%s.efi.stub" % (deploy_dir_image, target_arch)
    if not os.path.exists(stub):
        bb.fatal("uki-mender-ab: missing stub %s" % stub)
    ukify_cmd += " --stub %s" % stub

    uki_fstype = d.getVar('INITRAMFS_FSTYPES').split()[0]
    initramfs_image = "%s-%s.%s" % (
        d.getVar('INITRAMFS_IMAGE'), d.getVar('MACHINE'), uki_fstype)
    ukify_cmd += " --initrd=%s" % os.path.join(deploy_dir_image, initramfs_image)

    kernel_filename = d.getVar('UKI_KERNEL_FILENAME')
    kernel = "%s/%s" % (deploy_dir_image, kernel_filename)
    if not os.path.exists(kernel):
        bb.fatal("uki-mender-ab: missing kernel %s" % kernel)
    ukify_cmd += " --linux=%s" % kernel
    kver = d.getVar('KERNEL_VERSION')
    if kver:
        ukify_cmd += " --uname %s" % kver

    # Slot-B cmdline goes here
    ukify_cmd += " --cmdline='%s'" % d.getVar('UKI_CMDLINE_B')

    uki_devicetree = d.getVar('UKI_DEVICETREE')
    if uki_devicetree:
        for dtb in uki_devicetree.split():
            dtb_path = "%s/%s" % (deploy_dir_image, os.path.basename(dtb))
            if not os.path.exists(dtb_path):
                bb.fatal("uki-mender-ab: missing dtb %s" % dtb_path)
            ukify_cmd += " --devicetree %s" % dtb_path

    if os.path.exists(d.getVar('UKI_CONFIG_FILE')):
        ukify_cmd += " --config=%s" % d.getVar('UKI_CONFIG_FILE')

    ukify_cmd += " --tools=%s%s/lib/systemd/tools" % (
        d.getVar('RECIPE_SYSROOT_NATIVE'), d.getVar('prefix'))
    ukify_cmd += " --os-release=@%s%s/lib/os-release" % (
        d.getVar('RECIPE_SYSROOT'), d.getVar('prefix'))

    key = d.getVar('UKI_SB_KEY')
    if key:
        ukify_cmd += " --sign-kernel --secureboot-private-key='%s'" % key
    cert = d.getVar('UKI_SB_CERT')
    if cert:
        ukify_cmd += " --secureboot-certificate='%s'" % cert

    out_path = os.path.join(deploy_dir_image, d.getVar('UKI_FILENAME_B'))
    ukify_cmd += " --output=%s" % out_path

    bb.debug(2, "uki-mender-ab: %s" % ukify_cmd)
    bb.process.run(ukify_cmd, shell=True)

    # Stage both UKIs into the rootfs so a Mender artifact carries them.
    dst = "%s/usr/lib/mender" % d.getVar('IMAGE_ROOTFS')
    os.makedirs(dst, exist_ok=True)
    for fn in (d.getVar('UKI_FILENAME'), d.getVar('UKI_FILENAME_B')):
        src = os.path.join(deploy_dir_image, fn)
        if not os.path.exists(src):
            bb.fatal("uki-mender-ab: missing UKI for staging: %s" % src)
        shutil.copy2(src, os.path.join(dst, fn))

    # Generate the initial loader.conf with NO `default`: systemd-boot selects
    # by sort order (the shim relies on this for rollback -- see
    # IMAGE_EFI_BOOT_FILES above and mender-uki-shim.sh). bootimg_efi deploys
    # this to /loader/loader.conf on the ESP per IMAGE_EFI_BOOT_FILES.
    loader_conf = os.path.join(deploy_dir_image, "loader.conf")
    with open(loader_conf, "w") as f:
        f.write("timeout 3\n")
}
addtask do_uki_b after do_uki before do_deploy do_image_complete do_image_wic
do_uki_b[depends] += "systemd-boot:do_deploy virtual/kernel:do_deploy"
do_uki_b[dirs] = "${B}"

# do_uki (oe-core) and do_uki_b read the initramfs from DEPLOY_DIR_IMAGE under
# its link name (INITRAMFS_IMAGE-MACHINE.fstype) -- a symlink the initramfs
# image deploy creates pointing at the timestamped .rootfs artifact. On a CI
# rebuild where the initramfs image task is satisfied from cache (so it is not
# re-deployed) in a persistent build dir, that link can be absent or left
# dangling, and ukify then dies with FileNotFoundError on the initramfs (seen
# on qemuarm64-uki, runs #2361/#2362). Repair it from the real artifact before
# ukify runs, logging the deploy state so a genuine missing-initramfs (no real
# file to relink) fails loudly here rather than cryptically inside ukify.
do_uki[prefuncs] += "uki_stage_initramfs"
do_uki_b[prefuncs] += "uki_stage_initramfs"
python uki_stage_initramfs() {
    import os, glob, shutil
    deploy = d.getVar('DEPLOY_DIR_IMAGE')
    tmpdir = d.getVar('TMPDIR')
    initimg = d.getVar('INITRAMFS_IMAGE')
    machine = d.getVar('MACHINE')
    fstype = d.getVar('INITRAMFS_FSTYPES').split()[0]
    want = os.path.join(deploy, "%s-%s.%s" % (initimg, machine, fstype))

    if os.path.exists(want):
        bb.plain("uki: initramfs present at %s" % want)
        return

    # The persistent CI build dir can carry a valid do_image_complete stamp for
    # the initramfs while its deployed artifact is missing from DEPLOY_DIR_IMAGE
    # (deploy reclaimed, or the sstate input->output copy not re-landing it), so
    # do_uki cannot find it. The artifact does still exist in the initramfs
    # image's work/staging dir (RM_WORK_EXCLUDE keeps it), so locate the real
    # file there and stage it into DEPLOY_DIR_IMAGE under the link name do_uki
    # expects. Fail loudly if it is genuinely nowhere.
    pats = [
        os.path.join(deploy, "%s-%s*.%s" % (initimg, machine, fstype)),
        os.path.join(tmpdir, "work", "*", initimg, "*", "deploy-*",
                     "%s-%s*.%s" % (initimg, machine, fstype)),
    ]
    found = []
    for p in pats:
        found += [f for f in glob.glob(p) if os.path.isfile(f) and not os.path.islink(f)]
    bb.plain("uki: initramfs not in deploy; searched -> %s" % (found or "nothing"))
    if not found:
        bb.fatal("uki: no %s initramfs artifact for %s under %s -- the initramfs "
                 "image produced no deployable file" % (fstype, machine, tmpdir))
    found.sort(key=os.path.getmtime)
    src = found[-1]
    os.makedirs(deploy, exist_ok=True)
    shutil.copy2(src, want)
    bb.plain("uki: staged initramfs %s -> %s" % (src, want))
}
