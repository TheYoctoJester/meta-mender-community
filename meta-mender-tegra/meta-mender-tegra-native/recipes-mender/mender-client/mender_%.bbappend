# The on-device capsule package is a recommendation here, not a dependency,
# because nothing under this scheme reads it: the update module takes the capsule
# out of the artifact payload and stages that. Only the classic scheme's
# switch-rootfs state script reads the installed copy, from
# /opt/nvidia/UpdateCapsule/tegra-bl.cap, which is why that layer depends on it
# outright.
#
# The distinction earns its keep with the recovery system, which has to fit an
# 80 MiB partition: the capsule is around 11 MB installed, and a recommendation
# can be dropped with BAD_RECOMMENDATIONS while a dependency cannot be dropped at
# all. Ordinary images are unaffected, since recommendations install by default.
#
# What the module needs at runtime, mender-flash and the nvbootctrl and
# OsIndications helpers, the module recipe depends on itself. The common layer
# appends what both schemes need; :append fragments from both layers merge.
RRECOMMENDS:mender-update:append:tegra = " tegra-uefi-capsules"
