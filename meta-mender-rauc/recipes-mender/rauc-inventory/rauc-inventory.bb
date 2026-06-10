SUMMARY = "Mender inventory script reporting RAUC status"
DESCRIPTION = "Installs a mender-inventory-rauc script that reports the RAUC \
system state and per-slot installed bundle version / compatible / boot status \
as Mender device inventory, so a RAUC-managed A/B device's installed software \
is visible in the Mender backend."
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI = "file://mender-inventory-rauc"

S = "${UNPACKDIR}"

inherit allarch

# rauc provides the status command; jq parses its JSON. The mender client
# (mender-update) owns /usr/share/mender/inventory and runs the script.
RDEPENDS:${PN} = "rauc jq"

MENDER_INVENTORY_DIR = "${datadir}/mender/inventory"

do_install() {
    install -d "${D}${MENDER_INVENTORY_DIR}"
    install -m 0755 "${UNPACKDIR}/mender-inventory-rauc" \
        "${D}${MENDER_INVENTORY_DIR}/mender-inventory-rauc"
}

FILES:${PN} = "${MENDER_INVENTORY_DIR}/mender-inventory-rauc"
