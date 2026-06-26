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

# --- Build the initramfs in its own multiconfig -------------------------------
#
# uki.bbclass builds INITRAMFS_IMAGE in the *same* config as the UKI image and
# expects its .cpio.gz in this image's DEPLOY_DIR_IMAGE. Two images sharing one
# deploy dir is fragile: in the persistent CI build dir the initramfs artifact
# went missing from the shared deploy dir while its do_image_complete stamp
# stayed valid, so bitbake never redeployed it and do_uki died with "initramfs
# image was not deployed" (qemuarm64-uki, runs #2361-#2365).
#
# Build the initramfs in a dedicated multiconfig instead -- the idiomatic Yocto
# mechanism. It gets its own TMPDIR (hence its own deploy dir), so nothing else
# can evict its artifact, and we pull it via mcdepends. The kas wrapper enables
# it with:
#
#     BBMULTICONFIG              = "uki-initramfs"
#     INITRAMFS_MULTICONFIG      = "uki-initramfs"
#     INITRAMFS_DEPLOY_DIR_IMAGE = "${TOPDIR}/tmp-uki-initramfs/deploy/images/${MACHINE}"
#
# (the multiconfig is meta-mender-uki/conf/multiconfig/uki-initramfs.conf, which
# only redirects TMPDIR; MACHINE/DISTRO/sstate/DL_DIR are inherited from
# local.conf, so it yields the same initramfs as the stock same-config build.)
# With INITRAMFS_MULTICONFIG unset this falls back to uki.bbclass's stock
# same-config behaviour, so a plain local build is unaffected.

INITRAMFS_DEPLOY_DIR_IMAGE ?= "${DEPLOY_DIR_IMAGE}"

python () {
    mc = d.getVar('INITRAMFS_MULTICONFIG')
    initimg = d.getVar('INITRAMFS_IMAGE')
    if not mc or not initimg:
        return
    # Drop the stock same-config initramfs dependency uki.bbclass adds, so the
    # initramfs is not also built in this config, and pull it from the
    # multiconfig instead (only do_uki / do_uki_b consume the artifact).
    same = '%s:do_image_complete' % initimg
    for task in ('do_uki', 'do_uki_b', 'do_image_complete'):
        deps = d.getVarFlag(task, 'depends', True) or ''
        if same in deps:
            d.setVarFlag(task, 'depends', deps.replace(same, ' '))
    mcdep = ' mc:%s:%s:%s:do_image_complete' % (d.getVar('BB_CURRENT_MC') or '', mc, initimg)
    d.appendVarFlag('do_uki', 'mcdepends', mcdep)
    d.appendVarFlag('do_uki_b', 'mcdepends', mcdep)
}

# uki.bbclass's do_uki and our do_uki_b read the initramfs from this image's
# DEPLOY_DIR_IMAGE. When it is built in a separate multiconfig, copy the
# artifact from the multiconfig's deploy dir into this one (under the link name
# ukify expects) before either UKI task runs. A no-op for the stock same-config
# build, where INITRAMFS_DEPLOY_DIR_IMAGE is this image's own deploy dir.
do_uki[prefuncs] += "uki_stage_initramfs"
do_uki_b[prefuncs] += "uki_stage_initramfs"
python uki_stage_initramfs() {
    import os, glob, shutil
    deploy = d.getVar('DEPLOY_DIR_IMAGE')
    src_dir = d.getVar('INITRAMFS_DEPLOY_DIR_IMAGE')
    topdir = d.getVar('TOPDIR')
    initimg = d.getVar('INITRAMFS_IMAGE')
    machine = d.getVar('MACHINE')
    fstype = d.getVar('INITRAMFS_FSTYPES').split()[0]
    name = "%s-%s.%s" % (initimg, machine, fstype)
    want = os.path.join(deploy, name)
    if os.path.exists(want):
        return

    # Diagnostics: where do we expect it, and what is actually in the candidate
    # deploy dirs? (clean CI env is the only place we get reliable ground truth.)
    bb.plain("uki: want %s" % want)
    bb.plain("uki: INITRAMFS_DEPLOY_DIR_IMAGE=%s" % src_dir)
    for label, dpath in (("mc-deploy", src_dir), ("main-deploy", deploy)):
        if os.path.isdir(dpath):
            ents = [e for e in os.listdir(dpath) if initimg in e]
            bb.plain("uki: %s %s -> %s" % (label, dpath, ents or "(no initramfs entries)"))
        else:
            bb.plain("uki: %s %s -> MISSING DIR" % (label, dpath))

    # Find the deployed initramfs image wherever it landed and stage it under the
    # link name ukify expects. Search the mc/main deploy dirs and the whole mc
    # deploy tree.
    hits = []
    for base in (src_dir, deploy, os.path.join(topdir, "tmp-uki-initramfs", "deploy")):
        hits += glob.glob(os.path.join(base, "**", "%s-%s*.%s" % (initimg, machine, fstype)),
                          recursive=True)
    hits = [h for h in dict.fromkeys(hits) if os.path.isfile(h)]  # resolves valid symlinks
    bb.plain("uki: initramfs image hits -> %s" % (hits or "none"))
    if not hits:
        bb.fatal("uki: no deployable %s found for %s (see listing above)" % (name, initimg))
    hits.sort(key=os.path.getmtime)
    real = os.path.realpath(hits[-1])
    os.makedirs(deploy, exist_ok=True)
    if os.path.islink(want) or os.path.exists(want):
        os.remove(want)
    shutil.copy2(real, want)
    bb.plain("uki: staged initramfs %s -> %s" % (real, want))
}
