# The Tegra-native update scheme.
#
# A tegra-rootfs-image update module that drives nvbootctrl, the BSP partlabels
# and the UEFI capsule directly, in place of Mender's stock rootfs-image module
# and the adapters meta-mender-tegra-classic has to supply for it. The artifact
# it emits carries the tegra-rootfs-image payload type and the capsule alongside
# the rootfs, and keeps the canonical .mender name, since only the payload type
# inside it differs.
#
# This is the entry point for a native build. Inherit it instead of
# tegra-mender-common, which it pulls in itself:
#
#   INHERIT += "tegra-mender-native"

inherit tegra-mender-common

TEGRA_MENDER_SCHEME = "native"

IMAGE_CLASSES += "image_types_mender_tegra_native"

# Build a recovery system into the (otherwise empty) `recovery` partition.
#
# meta-tegra allocates that partition on nearly every Tegra layout and never fills
# it, while L4TLauncher will boot it both on request and, more usefully, by itself
# once no rootfs slot is bootable. Enabling this puts a RAM-only system there that
# mounts the Mender data partition, so it is the same device to the server, and
# runs the client in managed mode with the recovery-aware update module.
#
# Off by default. It is a feature of this scheme rather than a scheme of its own:
# the recovery context lives in tegra-rootfs-image, and the classic scheme's state
# scripts have no equivalent. Before the split that had to be asserted, since both
# were variables; now it is structural, because this toggle only exists in the
# layer that carries the module.
TEGRA_MENDER_RECOVERY ??= "0"

IMAGE_CLASSES += "${@'image_types_mender_tegra_recovery' if bb.utils.to_boolean(d.getVar('TEGRA_MENDER_RECOVERY')) else ''}"

# Same default meta-tegra uses in image_types_tegra.bbclass, restated here because
# that is a recipe class: recipes which do not inherit it, such as the one that
# builds the recovery boot image, cannot see the value and would otherwise
# size-check against an empty string. This class is global, so setting it here
# makes the partition size visible everywhere and gives a single place to raise it.
# Raising it changes the flash layout and needs a reflash.
TEGRA_RECOVERY_KERNEL_PART_SIZE ??= "83886080"

# The name of the boot image, set here rather than in the recipe class, because
# the storage-layout bbappends need it too and do not inherit that class.
TEGRA_MENDER_RECOVERY_BOOTIMG ?= "tegra-mender-recovery.img"

# Name the recovery partition in the flash layouts, so that flashing populates it.
# This is the whole reason the common layer's filename rewrite is driven by a
# variable: the entries go in from here and this layer needs no bbappend of its own
# on either storage-layout recipe.
#
# The _EXTRA half of the map is the right one: it is applied to every layout,
# including the one this layer set ships for the p3768 machines, which the map for
# NVIDIA's staged layouts must not touch. Getting this wrong is silent on exactly
# the machines with a custom layout, so see the comment in tegra-mender-layout.inc.
#
# An entry for a partition a given layout does not have costs nothing, so both
# spellings can be listed unconditionally. RECNAME is NVIDIA's placeholder, and
# the RECNAME to recovery substitution happens later, at image time in
# image_types_tegra.bbclass, so the layout still carries the placeholder when the
# rewrite runs. Listing both keeps this working if that ever changes.
#
# recovery-dtb is deliberately left out. BootAndroidStylePartition tolerates a
# recovery-dtb it cannot parse and keeps the devicetree the firmware already
# installed, which is the correct one for the board. Populating it would add a
# second copy of the DTB to keep in step with the kernel for no gain.
def tegra_mender_recovery_layout_entries(d):
    if not bb.utils.to_boolean(d.getVar('TEGRA_MENDER_RECOVERY')):
        return ''
    img = d.getVar('TEGRA_MENDER_RECOVERY_BOOTIMG')
    return ' RECNAME:%s recovery:%s' % (img, img)

TEGRA_MENDER_LAYOUT_FILENAMES_EXTRA:append = "${@tegra_mender_recovery_layout_entries(d)}"

# The recovery system needs the server URL and the tenant token, and it cannot get
# them from /etc/mender/mender.conf, because that lives in a rootfs slot and a
# device in recovery has usually lost both. Move them into the persistent
# configuration on the data partition instead, which the recovery system mounts.
#
# Both lines are required. mender-client-cpp.inc filters the persistent list
# against MENDER_CONFIGURATION_VARS, and TenantToken is not in meta-mender's
# default allowlist, so adding it only to the persistent list would silently do
# nothing.
#
# Note this *moves* the keys: mender-client-cpp.inc deletes migrated keys from the
# transient config, so they no longer appear in /etc/mender/mender.conf. That is an
# improvement for the rootfs image, which stops carrying the tenant token, but it
# means a device flashed before this was enabled has no persistent ServerURL, and
# updating it to an image built with this enabled would leave it unable to find the
# server. Enable this at flash time, not mid-life.
MENDER_CONFIGURATION_VARS:append = "${@' TenantToken' if bb.utils.to_boolean(d.getVar('TEGRA_MENDER_RECOVERY')) else ''}"
MENDER_PERSISTENT_CONFIGURATION_VARS:append = "${@' ServerURL TenantToken' if bb.utils.to_boolean(d.getVar('TEGRA_MENDER_RECOVERY')) else ''}"

# This class is inherited build-wide, so the appends below reach every image
# recipe in the build, not just the OS image. meta-tegra's helper images must be
# excluded from both, or:
#
#   - the initramfs images deadlock, because the native artifact depends on the
#     UEFI capsule and meta-tegra builds the capsule from the initramfs:
#       tegra-uefi-capsules:do_compile -> tegra-minimal-initramfs:do_image_complete
#         -> do_image_tegra_mender_native -> tegra-uefi-capsules:do_deploy
#   - the initramfs also gains the update module and its runtime dependencies
#     (mender-flash, tegra-redundant-boot-base, setup-nv-boot-control), which it
#     has no use for, and which then grow the capsule built from it, and so the
#     payload of every artifact.
#   - tegra-espimage otherwise emits a meaningless update artifact holding the
#     ESP contents.
#
# The skip list is matched as a substring of the image name. That is blunt: an
# image whose name merely contains "initramfs" is skipped too. It is preferred to
# naming meta-tegra's helper images exactly, which breaks silently whenever one
# is renamed. The failure modes are asymmetric, which is what settles it: a false
# skip means a missing artifact, which is noticed immediately, while a false
# include means a dependency loop or a bloated capsule, which is not.
TEGRA_MENDER_NATIVE_SKIP_IMAGES ?= "initramfs espimage"

# True unless the image being parsed is named in the skip list held by <var>.
# Shared, because the recovery staging class needs the same test over a different
# list, and two copies of four lines is how they drift apart.
def tegra_mender_image_wanted(d, var):
    name = d.getVar('IMAGE_BASENAME') or d.getVar('PN') or ''
    for skip in (d.getVar(var) or '').split():
        if skip in name:
            return False
    return True

def tegra_mender_native_enabled(d):
    return tegra_mender_image_wanted(d, 'TEGRA_MENDER_NATIVE_SKIP_IMAGES')

# The stock rootfs-image module is left in the image on purpose rather than
# surgically deleted. Under this scheme libubootenv-fake is not installed, so it
# fails immediately on the missing fw_printenv instead of running through a
# no-op fw_setenv and silently doing nothing. That is the loud failure we want
# if someone deploys an ordinary rootfs-image artifact here.
IMAGE_INSTALL:append:tegra = "${@' tegra-rootfs-update-module' if tegra_mender_native_enabled(d) else ''}"

# Swap the stock "mender" artifact for the module-image one. This has to be an
# :append:tegra plus a :remove:tegra, not a plain +=, because the tegra kas
# configurations set IMAGE_FSTYPES:tegra outright and that replaces anything
# appended to the unoverridden variable.
#
# The removal is not just tidiness. Both types write the artifact under the
# canonical .mender name, so leaving both in IMAGE_FSTYPES has the two do_image
# tasks writing the same path in IMGDEPLOYDIR, and whichever finishes last wins.
# A legacy artifact under the expected name is exactly the kind of thing that is
# only noticed on the device, so the check below refuses to build instead.
IMAGE_FSTYPES:append:tegra = "${@' tegra-mender-native' if tegra_mender_native_enabled(d) else ''}"
IMAGE_FSTYPES:remove:tegra = "mender"

# The :remove above makes this unreachable in an untouched configuration, since
# :remove wins over any assignment or append whatever the parse order. It is here
# for the configuration that overrides IMAGE_FSTYPES:remove:tegra itself, which
# puts "mender" back and is otherwise silent.
python () {
    fstypes = (d.getVar('IMAGE_FSTYPES') or '').split()
    if 'tegra-mender-native' in fstypes and 'mender' in fstypes:
        bb.fatal('IMAGE_FSTYPES contains both "mender" and "tegra-mender-native". '
                 'Both write the artifact under the same .mender name, so the two '
                 'do_image tasks would write one path and whichever finished last '
                 'would win. Take "mender" back out, or inherit '
                 'tegra-mender-classic instead.')
}
