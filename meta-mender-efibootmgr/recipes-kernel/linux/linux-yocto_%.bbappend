# EFI-stub + AHCI + efivarfs + builtin cmdline for the efibootmgr A/B demo.
# Only applies to the demo machine; other machines are untouched.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:qemux86-64 = " file://efibootmgr-stub.cfg"

# Warn loudly if the rootA PARTUUID was overridden but the static kernel
# fragment (which hardcodes it in CONFIG_CMDLINE) was not regenerated.
python () {
    if d.getVar('MACHINE') == 'qemux86-64':
        want = (d.getVar('EFIBOOTMGR_ROOTA_UUID') or '').strip()
        baked = 'aaaaaaaa-0000-0000-0000-00000000000a'
        if want and want != baked:
            bb.warn("EFIBOOTMGR_ROOTA_UUID=%s does not match the value baked "
                    "into efibootmgr-stub.cfg (%s); update the fragment's "
                    "CONFIG_CMDLINE to keep the first-boot fallback working."
                    % (want, baked))
}
