# For the reTerminal, provide a kiosk-mode weston.ini.
# The reterminal/ subdirectory is prepended to the file search path,
# so the base recipe's fetch of file://weston.ini will find our version.
FILESEXTRAPATHS:prepend:seeed-reterminal-mender := "${THISDIR}/reterminal:"
