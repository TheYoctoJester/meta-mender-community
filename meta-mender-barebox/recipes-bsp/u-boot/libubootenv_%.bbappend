# meta-mender-core's libubootenv bbappend adds an UNCONDITIONAL
#   do_compile[depends] += "u-boot:do_deploy"
# which assumes a U-Boot-based system. On a barebox system u-boot is not built
# (PREFERRED_PROVIDER_virtual/bootloader = barebox), so that dependency makes
# libubootenv -- and therefore the whole image -- unbuildable.
#
# libubootenv only needs the u-boot deploy artifact to seed an initial
# fw_env.config under the mender-uboot feature; with mender-uboot disabled we
# ship our own /etc/fw_env.config (mender-barebox-data) and pre-seed the env
# image ourselves (mender-barebox-ab.bbclass), so the u-boot dependency is not
# needed. Drop it when mender-uboot is off.
python () {
    if not bb.utils.contains('MENDER_FEATURES', 'mender-uboot', True, False, d):
        deps = (d.getVarFlag('do_compile', 'depends') or '').split()
        deps = [x for x in deps if x != 'u-boot:do_deploy']
        d.setVarFlag('do_compile', 'depends', ' '.join(deps))
}
