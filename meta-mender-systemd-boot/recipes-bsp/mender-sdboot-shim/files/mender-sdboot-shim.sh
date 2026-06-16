#!/bin/sh
# mender-sdboot-shim -- drop-in replacement for u-boot-fw-utils' fw_setenv /
# fw_printenv on a Mender + systemd-boot system that uses systemd's native
# Automatic Boot Assessment (boot counting) for A/B rollback.
#
# Mender's rootfs-image update module mutates persistent A/B state by calling
# `fw_setenv <var> <value>` / `fw_setenv <var>=<value>` / `fw_setenv -s -`
# (batch, "<var> <value>" lines on stdin) and reads it back with
# `fw_printenv <var>`. There is no U-Boot environment here, so we shim those.
#
# The Mender-visible state is a plain KEY=VALUE file on the data partition
# (so values set pre-reboot survive the rootfs swap). The systemd-boot side
# of the state lives entirely in files on the FAT ESP -- no EFI variables:
#
#   * /boot/loader/entries/mender-{a,b}.conf are Type #1 boot entries. A
#     trial slot's entry carries a boot counter in its filename, e.g.
#     mender-b+1-0.conf ("1 try left, 0 done"). systemd-boot decrements the
#     counter (by renaming) each time it selects the entry; at +0-N the
#     entry is "bad" and the firmware prefers the still-good committed slot.
#     That is the rollback -- in firmware, with no bootloader patch.
#   * /boot/loader/loader.conf `default` selects the preferred slot.
#   * /boot/EFI/Linux/mender-{a,b}/{bzImage,initrd} are the per-slot kernel
#     and initrd. On a slot flip we refresh the target slot's pair from that
#     slot's rootfs (/usr/lib/mender), which travels with the Mender
#     artifact -- so a kernel update propagates with the rootfs.
#
# Mapping of the Mender update flow:
#
#   ArtifactInstall  fw_setenv mender_boot_part=<new> upgrade_available=1
#                    -> refresh <new> slot kernel from the just-written
#                       inactive rootfs, write its entry WITH a boot counter
#                       (arm the trial), point `default` at it.
#   (reboot; systemd-boot decrements the counter and boots the trial slot)
#   ArtifactCommit   fw_setenv upgrade_available=0
#                    -> strip the counter from the committed slot's entry
#                       ("bless good"); it is now a permanent, good entry.
#   ArtifactRollback fw_setenv mender_boot_part=<old> upgrade_available=0
#                    -> point `default` back at <old> (already a good entry).
#   Automatic rollback: a trial that panics or is power-cycled before commit
#                    counts out; the firmware boots the committed slot, and
#                    Mender's ArtifactVerifyReboot sees the slot mismatch.
#
# init_state pre-seeds the two mender_*_canary variables so the rootfs-image
# update module's `set -e`-protected canary check does not abort the install.

set -e

STATE_DIR=/data/mender-sdboot
STATE_FILE=$STATE_DIR/state
# The ESP is mounted at /boot/efi (see mender-systemd-boot-ab.bbclass for why
# /boot/efi and not /boot). systemd-boot reads these same files from the ESP
# root at the firmware stage.
ESP_MOUNT=/boot/efi
ENTRIES_DIR=$ESP_MOUNT/loader/entries
LOADER_CONF=$ESP_MOUNT/loader/loader.conf
KERNEL_ROOTFS_DIR=/usr/lib/mender

# How many attempts a trial slot is armed with. Kept in sync with
# MENDER_SDBOOT_BOOT_TRIES at build time via @TRIES@.
BOOT_TRIES=@TRIES@

# Kernel command line tail (everything after root=PARTLABEL=...), kept in
# sync with MENDER_SDBOOT_APPEND at build time via @APPEND@.
APPEND="@APPEND@"

init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        mkdir -p "$STATE_DIR"
        cat >"$STATE_FILE" <<EOF
mender_boot_part=2
mender_boot_part_hex=2
upgrade_available=0
bootcount=0
mender_check_saveenv_canary=1
mender_saveenv_canary=1
sdboot_gen=1
sdboot_ver_a=1
sdboot_ver_b=0
EOF
    fi
}

read_var() {
    grep -E "^$1=" "$STATE_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-
}

write_var() {
    key=$1
    val=$2
    tmp=$(mktemp)
    grep -vE "^$key=" "$STATE_FILE" >"$tmp" 2>/dev/null || true
    printf '%s=%s\n' "$key" "$val" >>"$tmp"
    mv "$tmp" "$STATE_FILE"
}

# Map a Mender partition number to the slot letter, rootfs partlabel and the
# ESP sub-directory holding that slot's kernel/initrd.
slot_letter() { case "$1" in 2) echo a ;; 3) echo b ;; *) return 1 ;; esac; }
slot_partlabel() { case "$1" in 2) echo mender-rootfsa ;; 3) echo mender-rootfsb ;; *) return 1 ;; esac; }

# Write slot <letter>'s Type #1 entry. With a non-empty <tries> the filename
# carries the boot counter (arming a trial); empty <tries> writes the plain,
# "good" (blessed) entry. The entry's `version` is taken from the per-slot
# state variable sdboot_ver_<letter>; systemd-boot prefers the highest
# non-bad version, so this is what selects the slot (no explicit `default`).
# Any prior variant for this slot is removed first.
write_entry() {
    letter=$1
    tries=$2
    case "$letter" in
        a) partlabel=mender-rootfsa ;;
        b) partlabel=mender-rootfsb ;;
        *) echo "mender-sdboot-shim: bad slot $letter" >&2; return 1 ;;
    esac
    ver=$(read_var "sdboot_ver_$letter")
    [ -n "$ver" ] || ver=0
    mkdir -p "$ENTRIES_DIR"
    rm -f "$ENTRIES_DIR/mender-$letter.conf" "$ENTRIES_DIR"/mender-"$letter"+*.conf
    if [ -n "$tries" ]; then
        fname="mender-$letter+$tries-0.conf"
    else
        fname="mender-$letter.conf"
    fi
    cat >"$ENTRIES_DIR/$fname" <<EOF
title Mender slot $(echo "$letter" | tr a-z A-Z)
sort-key mender
version $ver
linux /EFI/Linux/mender-$letter/bzImage
initrd /EFI/Linux/mender-$letter/initrd
options root=PARTLABEL=$partlabel $APPEND
EOF
}

# Assign the target slot the next (highest) version, so a good trial outranks
# the committed slot and, after commit, stays the default. Monotonic across
# flips; the value is just a sort key.
bump_version() {
    letter=$1
    gen=$(read_var sdboot_gen)
    [ -n "$gen" ] || gen=1
    gen=$((gen + 1))
    write_var sdboot_gen "$gen"
    write_var "sdboot_ver_$letter" "$gen"
}

# Refresh the target slot's kernel + initrd on the ESP from that slot's
# rootfs. If the target slot is the currently-mounted root, read from /;
# otherwise mount the slot's partition read-only (this is the path taken at
# ArtifactInstall, where the target is the freshly-written inactive slot).
refresh_kernel() {
    letter=$1
    part=$2
    partlabel=$(slot_partlabel "$part") || return 1
    target_dev="/dev/disk/by-partlabel/$partlabel"
    dst="$ESP_MOUNT/EFI/Linux/mender-$letter"

    # Resolve both sides to a real device node: findmnt reports the
    # /dev/disk/by-partlabel symlink, readlink -f the partition. Without
    # resolving, the comparison is always false, and a flip whose target is
    # the running slot (e.g. ArtifactCommit re-setting mender_boot_part) would
    # wrongly re-mount and re-copy, clobbering the committed slot's kernel.
    cur=$(findmnt -n -o SOURCE / 2>/dev/null | head -n 1)
    cur=$(readlink -f "$cur" 2>/dev/null || echo "$cur")
    tdev=$(readlink -f "$target_dev" 2>/dev/null || echo "$target_dev")

    mnt=""
    if [ "$tdev" = "$cur" ]; then
        src="$KERNEL_ROOTFS_DIR"
    else
        mnt=$(mktemp -d)
        # The inactive slot was just written by Mender (raw writes to the
        # block device). The kernel can hold a stale page/buffer cache for
        # that device from a previous read, so a fresh read-only mount may
        # otherwise see the slot's PREVIOUS contents and we would stage the
        # old kernel instead of the just-installed one. Force the caches to
        # be dropped (on the resolved device node, not the symlink) so the
        # mount reflects what Mender actually wrote.
        rdev=$(readlink -f "$target_dev" 2>/dev/null || echo "$target_dev")
        sync
        blockdev --flushbufs "$rdev" 2>/dev/null || true
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        mount -o ro "$rdev" "$mnt"
        src="$mnt$KERNEL_ROOTFS_DIR"
    fi

    if [ -f "$src/bzImage" ] && [ -f "$src/initrd" ]; then
        mkdir -p "$dst"
        cp -f "$src/bzImage" "$dst/bzImage"
        cp -f "$src/initrd" "$dst/initrd"
    else
        echo "mender-sdboot-shim: WARNING $src missing kernel/initrd; ESP not refreshed" >&2
    fi

    if [ -n "$mnt" ]; then
        umount "$mnt" 2>/dev/null || true
        rmdir "$mnt" 2>/dev/null || true
    fi
    sync
}

# Point the target slot at the freshly-staged kernel and make it the
# preferred entry by giving it the next-highest version. With an upgrade in
# flight it is armed with a boot counter (a trial that can be rolled back);
# otherwise it is written as a plain good entry (the committed default, as on
# an ArtifactRollback that points mender_boot_part back at the old slot).
setup_target_slot() {
    part=$1
    letter=$(slot_letter "$part") || {
        echo "mender-sdboot-shim: invalid mender_boot_part=$part" >&2
        return 1
    }
    refresh_kernel "$letter" "$part"
    bump_version "$letter"
    if [ "$(read_var upgrade_available)" = "1" ]; then
        write_entry "$letter" "$BOOT_TRIES"
    else
        write_entry "$letter" ""
    fi
    sync
}

# Commit: strip the boot counter from the committed slot's entry so it is a
# permanent good entry (the file-level equivalent of `systemd-bless-boot good`),
# keeping its (highest) version so it remains the default.
commit_current_slot() {
    part=$(read_var mender_boot_part)
    letter=$(slot_letter "$part") || return 0
    write_entry "$letter" ""
    sync
}

# Apply a set of "key value" / "key=value" assignments, then act once on the
# resulting state (so the order of keys within a batch does not matter).
apply_assignments() {
    saw_boot_part=0
    saw_upgrade=0
    while IFS= read -r line; do
        case "$line" in
            ""|\#*) continue ;;
        esac
        case "$line" in
            *=*) k=${line%%=*}; v=${line#*=} ;;
            *)   k=${line%% *}; v=${line#"$k"}; v=${v# } ;;
        esac
        write_var "$k" "$v"
        [ "$k" = "mender_boot_part" ] && saw_boot_part=1
        [ "$k" = "upgrade_available" ] && saw_upgrade=1
    done

    if [ "$saw_boot_part" = "1" ]; then
        setup_target_slot "$(read_var mender_boot_part)"
    elif [ "$saw_upgrade" = "1" ] && [ "$(read_var upgrade_available)" = "0" ]; then
        commit_current_slot
    fi
}

cmd=$(basename "$0")

case "$cmd" in
    fw_printenv)
        init_state
        if [ $# -eq 0 ]; then
            cat "$STATE_FILE"
        else
            # u-boot's fw_printenv accepts several names and prints each;
            # it exits non-zero if any requested name is undefined, but still
            # prints the ones that are defined.
            rc=0
            for k in "$@"; do
                if grep -qE "^$k=" "$STATE_FILE"; then
                    printf '%s=%s\n' "$k" "$(read_var "$k")"
                else
                    echo "## Error: \"$k\" not defined" >&2
                    rc=1
                fi
            done
            exit $rc
        fi
        ;;
    fw_setenv)
        init_state
        if [ "$1" = "-s" ]; then
            src=${2:--}
            if [ "$src" = "-" ]; then
                input=$(cat -)
            else
                input=$(cat "$src")
            fi
            printf '%s\n' "$input" | apply_assignments
            exit 0
        fi
        if [ $# -eq 2 ]; then
            printf '%s %s\n' "$1" "$2" | apply_assignments
        elif [ $# -eq 1 ]; then
            printf '%s\n' "$1" | apply_assignments
        else
            echo "Usage: fw_setenv KEY VALUE | KEY=VALUE | -s FILE|-" >&2
            exit 1
        fi
        ;;
    mender-sdboot-shim)
        init_state
        cat "$STATE_FILE"
        ;;
    *)
        echo "mender-sdboot-shim: unknown invocation as $cmd" >&2
        exit 1
        ;;
esac
