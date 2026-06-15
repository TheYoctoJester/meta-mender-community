#!/bin/bash
# First-boot provisioning for the efibootmgr A/B demo.
#
# On a fresh device the UEFI variable store has no Mender boot entries: the very
# first boot reaches Linux through the firmware's removable-media fallback
# (EFI/BOOT/bootx64.efi, using the kernel's builtin CONFIG_CMDLINE -> rootA).
# This service runs once and creates the two persistent per-slot entries the
# Update Module then switches between:
#
#   "Mender slot A" -> \EFI\mender-a\bzImage.efi  -u root=PARTUUID=<rootA>
#   "Mender slot B" -> \EFI\mender-b\bzImage.efi  -u root=PARTUUID=<rootB>
#
# BootOrder is set to A first, because the build-time active slot is rootA.

set -eu

MARKER_DIR="/data/mender-efibootmgr"
MARKER="${MARKER_DIR}/bootentries-done"
ESP_MOUNT="/boot/efi"
KARGS="rootwait rw console=ttyS0,115200"

log() { echo "mender-efibootmgr-bootentry: $*"; }

[ -f "$MARKER" ] && exit 0

if [ ! -d /sys/firmware/efi ]; then
    log "not booted via UEFI (/sys/firmware/efi absent); skipping"
    exit 0
fi

# systemd normally mounts efivarfs; make sure it is there for efibootmgr.
if ! mountpoint -q /sys/firmware/efi/efivars; then
    mount -t efivarfs none /sys/firmware/efi/efivars 2>/dev/null || true
fi

ESP_DEV=$(findmnt -n -o SOURCE "$ESP_MOUNT" 2>/dev/null || true)
if [ -z "$ESP_DEV" ]; then
    log "ESP not mounted at ${ESP_MOUNT}; cannot create boot entries"
    exit 1
fi
DISK=$(echo "$ESP_DEV" | sed 's/p\?[0-9]*$//')
PART=$(echo "$ESP_DEV" | grep -o '[0-9]*$')

UUID_A=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/rootA)
UUID_B=$(blkid -s PARTUUID -o value /dev/disk/by-partlabel/rootB)
[ -n "$UUID_A" ] && [ -n "$UUID_B" ] || { log "could not read rootA/rootB PARTUUIDs"; exit 1; }

# bootnum_for_label <label> -> first matching Boot#### number (without 'Boot').
# efibootmgr prints "Boot0005* <label>\t<device path...>", so the label is
# delimited by a leading "* " and a trailing TAB, not the end of line.
bootnum_for_label() {
    local tab line
    tab=$(printf '\t')
    line=$(efibootmgr | grep -F "* $1${tab}" | head -n1) || true
    [ -n "$line" ] || return 0
    line=${line#Boot}
    echo "${line%%\**}"
}

create_entry() {
    # $1 label  $2 loader  $3 root PARTUUID
    if [ -n "$(bootnum_for_label "$1")" ]; then
        log "entry '$1' already exists; leaving it"
        return
    fi
    log "creating entry '$1' -> $2 (root=PARTUUID=$3)"
    efibootmgr -c -d "$DISK" -p "$PART" -L "$1" -l "$2" \
        -u "root=PARTUUID=$3 $KARGS" >/dev/null
}

create_entry "Mender slot A" '\EFI\mender-a\bzImage.efi' "$UUID_A"
create_entry "Mender slot B" '\EFI\mender-b\bzImage.efi' "$UUID_B"

NUM_A=$(bootnum_for_label "Mender slot A")
NUM_B=$(bootnum_for_label "Mender slot B")
if [ -n "$NUM_A" ] && [ -n "$NUM_B" ]; then
    log "setting BootOrder ${NUM_A},${NUM_B} (slot A is the committed default)"
    efibootmgr -o "${NUM_A},${NUM_B}" >/dev/null
fi

mkdir -p "$MARKER_DIR"
touch "$MARKER"
log "done"
