#!/bin/sh
# Build a 'rootfs-image-fwu' Mender Artifact for the meta-mender-fwu demo.
#
# The rootfs-image-fwu Update Module's payload contract (see
# recipes-extended/mender-update-module-fwu/files/rootfs-image-fwu) is a single
# file that is ALREADY a UEFI FMP capsule: mkeficapsule wraps the demo
# rootfs.ext4 against the FWU rootfs image-type GUID, and this script then packs
# that capsule into a Mender module-image Artifact of type rootfs-image-fwu. On
# the device the module drops the capsule into the ESP; U-Boot's capsule-on-disk
# scanner applies it to the inactive bank on the next boot and FWU flips banks.
#
# We build the OTA artifact out of band (not via IMAGE_FSTYPES += "mender",
# which yields a plain rootfs-image artifact the FWU module cannot consume).
#
# Requires mkeficapsule (u-boot-tools) and mender-artifact on PATH -- e.g. from
# `kas shell yocto/wrynose/floating/qemuarm64-fwu.yml -c bash`, or downloaded
# release binaries. Either tool can be pointed at an explicit path via the
# MKEFICAPSULE / MENDER_ARTIFACT environment variables (CI uses this to mix a
# kas-shell mkeficapsule with a downloaded mender-artifact).
#
# Usage:
#   make-artifact.sh <rootfs.ext4> <artifact-name> <output.mender> [device-type] [fw-version]
#
# Example:
#   make-artifact.sh \
#       build/tmp/deploy/images/qemuarm64-secureboot/core-image-fwu-test-qemuarm64-secureboot.rootfs.ext4 \
#       fwu-wrynose-v2 \
#       /tmp/fwu-wrynose-v2.mender
#
# fw-version defaults to the trailing digits of the artifact name (fwu-wrynose-v2
# -> 2). The FMP firmware version must exceed the one already installed, so bump
# the artifact name's trailing number between deployments.

set -eu

ROOTFS="${1:?rootfs ext4 image required}"
ARTIFACT_NAME="${2:?artifact name required}"
OUTPUT="${3:?output .mender path required}"
DEVICE_TYPE="${4:-qemuarm64-secureboot}"
FW_VERSION="${5:-}"

# FWU rootfs image type. Registered in U-Boot's fw_images[] at image_index 3 by
# recipes-bsp/u-boot/files/0003-board-qemu-arm-register-FWU-image-types-with-FMP.patch;
# the capsule GUID must match so the FMP routes it to the FWU agent / rootfs bank.
FWU_ROOTFS_IMAGE_TYPE_UUID="f1d3e7a0-5f6e-4b8c-9d2e-1a3b5c7d9e2f"
FWU_ROOTFS_IMAGE_INDEX="3"

MKEFICAPSULE="${MKEFICAPSULE:-mkeficapsule}"
MENDER_ARTIFACT="${MENDER_ARTIFACT:-mender-artifact}"

[ -f "$ROOTFS" ] || { echo "rootfs image not found: $ROOTFS" >&2; exit 1; }
command -v "$MKEFICAPSULE" >/dev/null 2>&1 || {
    echo "mkeficapsule not found (set MKEFICAPSULE or run inside a kas shell)" >&2
    exit 1
}
command -v "$MENDER_ARTIFACT" >/dev/null 2>&1 || {
    echo "mender-artifact not found (set MENDER_ARTIFACT or add it to PATH)" >&2
    exit 1
}

# Derive the FMP firmware version from the artifact name's trailing digits.
if [ -z "$FW_VERSION" ]; then
    FW_VERSION="$(printf '%s' "$ARTIFACT_NAME" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
    [ -n "$FW_VERSION" ] || FW_VERSION="2"
fi

CAPSULE="$(dirname "$OUTPUT")/$(basename "$ARTIFACT_NAME").cap"

echo "make-artifact: capsule rootfs=$ROOTFS guid=$FWU_ROOTFS_IMAGE_TYPE_UUID index=$FWU_ROOTFS_IMAGE_INDEX fw-version=$FW_VERSION"
"$MKEFICAPSULE" \
    --index "$FWU_ROOTFS_IMAGE_INDEX" \
    --guid "$FWU_ROOTFS_IMAGE_TYPE_UUID" \
    --fw-version "$FW_VERSION" \
    "$ROOTFS" "$CAPSULE"

echo "make-artifact: artifact name=$ARTIFACT_NAME type=rootfs-image-fwu device=$DEVICE_TYPE"
"$MENDER_ARTIFACT" write module-image \
    --type rootfs-image-fwu \
    --artifact-name "$ARTIFACT_NAME" \
    --device-type "$DEVICE_TYPE" \
    --file "$CAPSULE" \
    --output-path "$OUTPUT"

echo "wrote $OUTPUT (type=rootfs-image-fwu, name=$ARTIFACT_NAME, device=$DEVICE_TYPE, fw-version=$FW_VERSION)"
