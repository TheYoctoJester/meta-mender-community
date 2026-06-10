#!/bin/sh
# mender-uki-shim — drop-in replacement for u-boot-fw-utils' fw_setenv /
# fw_printenv on a Mender + UKI + systemd-boot system.
#
# Mender's standard client mutates persistent A/B state by calling
# `fw_setenv <var> <value>` (or `fw_setenv <var>=<value>` or, in batch mode,
# `fw_setenv -s <file>|-` reading "<var> <value>" lines from a file/stdin)
# and reads it back with `fw_printenv <var>`. On a systemd-boot UKI system
# there is no U-Boot environment to write into — so we shim those commands.
#
# Persistent state lives in /data/mender-uki/state (a plain KEY=VALUE file
# on the data partition, deliberately NOT on the rootfs, so values set by
# mender pre-reboot survive the rootfs swap of an OTA). When
# `mender_boot_part` changes we additionally:
#
#   1. Copy /usr/lib/mender/uki-{a,b}.efi (which travels with the rootfs)
#      to /boot/EFI/Linux/, ensuring the ESP always carries the matching
#      UKI for whichever rootfs slot we are about to boot.
#   2. Rewrite the `default` line in /boot/loader/loader.conf to point at
#      the new UKI. This is the durable mechanism on platforms where U-Boot
#      is the UEFI runtime (qemuarm64-secureboot) because U-Boot cannot
#      persist EFI variables to flash; `bootctl set-default` is then also
#      called as best-effort but its effect is lost on the next boot if
#      efivar writes don't stick.
#
# init_state pre-seeds the two `mender_*_canary` variables so the mender
# rootfs-image update module's `set -e`-protected canary check
# (fw_printenv mender_check_saveenv_canary) doesn't kill the install with
# an "undefined" exit-1.

set -e

# /data is the Mender persistent-storage partition (mounted from a separate
# GPT partition labeled mender-data). Putting our state here means slot A
# and slot B see the same file, so values set by mender pre-reboot (e.g.
# `upgrade_available=1`) survive the slot flip and are readable by the
# mender client running on the freshly-installed rootfs after reboot.
STATE_FILE=/data/mender-uki/state
ESP_MOUNT=/boot
UKI_ROOTFS_DIR=/usr/lib/mender
UKI_A=uki-a.efi
UKI_B=uki-b.efi

init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        cat >"$STATE_FILE" <<EOF
mender_boot_part=2
mender_boot_part_hex=2
upgrade_available=0
bootcount=0
mender_check_saveenv_canary=1
mender_saveenv_canary=1
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

flip_boot_slot() {
    part=$1
    case "$part" in
        2) uki=$UKI_A ;;
        3) uki=$UKI_B ;;
        *)
            echo "mender-uki-shim: invalid mender_boot_part=$part (expected 2 or 3)" >&2
            return 1
            ;;
    esac
    if [ -f "$UKI_ROOTFS_DIR/$uki" ]; then
        mkdir -p "$ESP_MOUNT/EFI/Linux"
        cp -f "$UKI_ROOTFS_DIR/$uki" "$ESP_MOUNT/EFI/Linux/$uki"
    else
        echo "mender-uki-shim: WARNING $UKI_ROOTFS_DIR/$uki missing; ESP not refreshed" >&2
    fi
    # Persist the selection via systemd-boot's loader.conf (file-based default).
    # bootctl set-default writes the LoaderEntryDefault EFI variable; on
    # qemuarm64-secureboot the U-Boot UEFI runtime cannot persist EFI vars to
    # ESP, so file-based loader.conf is the only reliable handle.
    loader_conf=$ESP_MOUNT/loader/loader.conf
    mkdir -p "$(dirname "$loader_conf")"
    tmp=$(mktemp)
    if [ -f "$loader_conf" ]; then
        grep -vE '^default ' "$loader_conf" >"$tmp" 2>/dev/null || true
    fi
    printf 'default %s\n' "$uki" >>"$tmp"
    mv "$tmp" "$loader_conf"
    # Also try bootctl as a best-effort -- on platforms with persistent
    # efivars this gives the in-memory state to systemd-boot for the next
    # boot's LoaderEntryDefault read.
    if command -v bootctl >/dev/null 2>&1; then
        bootctl set-default "$uki" 2>/dev/null || true
    fi
    sync
}

cmd=$(basename "$0")

case "$cmd" in
    fw_printenv)
        init_state
        if [ $# -eq 0 ]; then
            cat "$STATE_FILE"
        else
            val=$(read_var "$1")
            if [ -z "$val" ]; then
                echo "## Error: \"$1\" not defined" >&2
                exit 1
            fi
            printf '%s=%s\n' "$1" "$val"
        fi
        ;;
    fw_setenv)
        init_state
        # Batch mode: u-boot's fw_setenv -s <file>  reads "<key> <value>" pairs
        # from a file (or stdin if file is "-"). The Mender rootfs-image update
        # module uses this to commit several vars (mender_boot_part,
        # upgrade_available, ...) atomically. Handle it here.
        if [ "$1" = "-s" ]; then
            src=${2:--}
            if [ "$src" = "-" ]; then
                input=$(cat -)
            else
                input=$(cat "$src")
            fi
            printf '%s\n' "$input" | while IFS= read -r line; do
                case "$line" in
                    ""|\#*) continue ;;
                esac
                case "$line" in
                    *=*) k=${line%%=*}; v=${line#*=} ;;
                    *)   k=${line%% *}; v=${line#"$k"}; v=${v# } ;;
                esac
                write_var "$k" "$v"
                if [ "$k" = "mender_boot_part" ] && [ -n "$v" ]; then
                    flip_boot_slot "$v"
                fi
            done
            exit 0
        fi
        if [ $# -eq 2 ]; then
            key=$1
            val=$2
        elif [ $# -eq 1 ]; then
            case "$1" in
                *=*) key=${1%%=*}; val=${1#*=} ;;
                *)   key=$1; val= ;;
            esac
        else
            echo "Usage: fw_setenv KEY VALUE | fw_setenv KEY=VALUE | fw_setenv -s FILE|- " >&2
            exit 1
        fi
        write_var "$key" "$val"
        if [ "$key" = "mender_boot_part" ] && [ -n "$val" ]; then
            flip_boot_slot "$val"
        fi
        ;;
    mender-uki-shim)
        init_state
        cat "$STATE_FILE"
        ;;
    *)
        echo "mender-uki-shim: unknown invocation as $cmd" >&2
        exit 1
        ;;
esac
