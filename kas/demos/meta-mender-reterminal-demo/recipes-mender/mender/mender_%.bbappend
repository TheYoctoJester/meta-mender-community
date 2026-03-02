FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-Add-D-Bus-state-signal-to-mender-update-daemon.patch \
"

FILES:mender-update:append = " \
    ${datadir}/dbus-1/system.d/io.mender.UpdateManager.conf \
"
