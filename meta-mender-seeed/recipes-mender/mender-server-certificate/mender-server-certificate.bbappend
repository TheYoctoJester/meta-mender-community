# Fix postinstall to pass sysroot as argument instead of env var.
# The update-ca-certificates script expects --sysroot, not SYSROOT env.
# Without this, the postinstall fails in restricted environments (e.g. LXC).
pkg_postinst:${PN} () {
    if [ -n "$D" ]; then
        $D${sbindir}/update-ca-certificates --sysroot "$D"
    else
        update-ca-certificates
    fi
}
