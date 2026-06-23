FILESEXTRAPATHS:prepend := "${THISDIR}/files/${SOC_FAMILY}:${THISDIR}/files:"

SRC_URI += " \
    file://fstab.append \
"

do_install:append () {
    cat ${UNPACKDIR}/fstab.append >> ${D}${sysconfdir}/fstab
    # /boot mount point (/var/lib/mender is provided by the mender packages and
    # is where vda4 mounts directly for OTA-persistent Mender state).
    install -d -m 0755 ${D}/boot
}
