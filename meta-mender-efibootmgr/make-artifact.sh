#!/bin/sh
# Wrap a built rootfs ext4 image into a Mender Artifact of the custom
# 'efibootmgr-rootfs' Update Module type.
#
# The payload is a plain rootfs.ext4; the efibootmgr-rootfs module on the device
# dd's it to the inactive slot and switches the UEFI boot manager. We build the
# artifact out of band (rather than via IMAGE_FSTYPES += "mender") to avoid
# colliding with meta-mender's built-in rootfs-image artifact generation.
#
# Requires mender-artifact on PATH (e.g. from `kas shell ... -c bash`, or a
# downloaded release binary).
#
# Usage:
#   make-artifact.sh <rootfs.ext4> <artifact-name> <output.mender> [device-type]
#
# Example:
#   make-artifact.sh \
#       build/tmp/deploy/images/qemux86-64/mender-efibootmgr-image-qemux86-64.ext4 \
#       efibootmgr-demo-v2 \
#       /tmp/efibootmgr-demo-v2.mender

set -eu

ROOTFS="${1:?rootfs ext4 image required}"
ARTIFACT_NAME="${2:?artifact name required}"
OUTPUT="${3:?output .mender path required}"
DEVICE_TYPE="${4:-qemux86-64}"

command -v mender-artifact >/dev/null 2>&1 || {
    echo "mender-artifact not found on PATH" >&2
    exit 1
}

mender-artifact write module-image \
    --type efibootmgr-rootfs \
    --artifact-name "$ARTIFACT_NAME" \
    --device-type "$DEVICE_TYPE" \
    --file "$ROOTFS" \
    --output-path "$OUTPUT"

echo "wrote $OUTPUT (type=efibootmgr-rootfs, name=$ARTIFACT_NAME, device=$DEVICE_TYPE)"
