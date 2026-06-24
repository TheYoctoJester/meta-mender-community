do_configure:prepend() {
	if [ -n "${MENDER_FEATURES}" ]; then
		bbwarn "having both the Mender integration and the meta-mender-client-only layer enabled will cause unexpected effects!"
	fi
}

do_compile:append() {
    echo "device_type=${MACHINE}" > ${B}/device_type
}

do_install:append() {
    install -m 755 -d ${D}/${localstatedir}/lib/mender
    install -m 444 ${B}/device_type ${D}/${localstatedir}/lib/mender/
}

RDEPENDS:${PN} = " ca-certificates"

# wrynose meta-mender (6.0.0) ships a broken version-inventory-script: it installs
# /usr/share/mender/inventory/mender-inventory-client-version but does not package
# the file, so the mender recipe's do_package QA fails. The client-only demos do
# not need the mender_client_version inventory attribute, so drop the offending
# PACKAGECONFIG entries here -- centralised for every meta-mender-client-only
# consumer instead of being repeated in each demo's kas config (rauc, swupdate).
# A no-op if the entries are not present.
PACKAGECONFIG:remove = "version-inventory-script version-inventory-script-strict"