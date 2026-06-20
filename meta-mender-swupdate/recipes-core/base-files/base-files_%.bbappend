FILESEXTRAPATHS:prepend := "${THISDIR}/files/${SOC_FAMILY}:${THISDIR}/files:"

SRC_URI += " \
    file://fstab.append \
"

do_install:append () {
    cat ${UNPACKDIR}/fstab.append >> ${D}${sysconfdir}/fstab
    # Mount points for the fstab entries above.
    install -d -m 0755 ${D}/boot ${D}/data
}
