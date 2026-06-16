#!/bin/sh
# mender-uki-shim — fw_setenv/fw_printenv shim for Mender on a UKI +
# systemd-boot system, using systemd-boot's BOOT COUNTING (automatic boot
# assessment) as the A/B rollback engine.
#
# Background
# ----------
# Mender's rootfs-image update module drives A/B purely through
# `fw_setenv`/`fw_printenv` on a handful of variables:
#
#   mender_boot_part   - which rootfs partition to boot (2 = slot A, 3 = B)
#   upgrade_available  - 1 while a freshly-installed slot is on trial,
#                        cleared to 0 by `mender commit` (and on rollback
#                        finalisation)
#   bootcount          - Mender's own trial counter (NOT used here; the
#                        retry count lives in the systemd-boot filename)
#   mender_*_canary    - sanity flags the update module's `set -e` path reads
#
# On a systemd-boot UKI system there is no U-Boot environment to write, so we
# shim those commands.
#
# Selection model: sort order, NOT loader.conf `default`
# ------------------------------------------------------
# systemd-boot 259's boot_entry_compare() (src/boot/boot.c) orders entries
# with `tries_left == 0` (a "bad", exhausted trial) LAST, and otherwise --
# for same-version UKIs with no embedded sort-key -- by id descending. Its
# default-entry selection honours a loader.conf `default` pattern *without*
# any bad-entry check (config_select_default_entry -> config_find_entry), so
# pinning `default` to the trial slot would keep booting it even after its
# counter hit zero -- defeating rollback. We therefore set NO `default` and
# let the sort decide:
#
#   * The trial image is staged under a filename that sorts BEFORE the
#     committed one ("uki-update" > "uki-current" by id), so while it still
#     has tries left it is the first good entry and boots.
#   * systemd-boot decrements its counter each boot (uki-update+3.efi ->
#     uki-update+2-1.efi -> ...). When it reaches uki-update+0-N.efi it is
#     "bad", sorted last, and systemd-boot automatically falls back to the
#     committed "uki-current.efi" -- the rollback, with no userspace and no
#     watchdog. This is symmetric: it does not depend on which physical slot
#     (A or B) is the trial, only on the uki-update vs uki-current names.
#
# On commit the trial is "blessed" by renaming it to uki-current.efi (which
# both strips the counter and promotes it to the permanent image), replacing
# the previous committed image.
#
# Why we do the bless/rename ourselves instead of `systemd-bless-boot good`
# -------------------------------------------------------------------------
# systemd-bless-boot finds the entry via the LoaderBootCountPath EFI variable
# that systemd-boot passes to the OS through efivarfs. On qemuarm64-secureboot
# the UEFI runtime is U-Boot, which does not reliably expose loader-set EFI
# variables to Linux (the same limitation that makes `bootctl set-default`
# best-effort). The counter *decrement* and bad-entry *fallback*, by contrast,
# are plain renames systemd-boot performs on the FAT ESP and need no
# EFI-variable runtime access, so they work regardless. systemd-bless-boot.service
# is masked by the recipe so it cannot race us.
#
# Why mender_boot_part is read by introspection, not from stored state
# --------------------------------------------------------------------
# systemd-boot selects the slot independently of Mender and does not write
# back any Mender state on an automatic rollback. So `fw_printenv
# mender_boot_part` derives the answer from reality: each slot's UKI bakes its
# own root=PARTLABEL=mender-rootfs{a,b}, so the running slot is unambiguous
# from /proc/cmdline (or the mounted root). Mender merely observes it, which
# makes rollback detection correct for free. The slot we were *asked* to trial
# is remembered separately as `trial_part` so commit (healthy, on the trial
# slot) can be told apart from rollback finalisation (back on the committed
# slot).

set -e

# /data is the Mender persistent-storage partition. Putting our state here
# means slot A and slot B see the same file across a rootfs swap.
STATE_FILE=/data/mender-uki/state
# Both UKIs travel with the rootfs (staged here by uki-mender-ab.bbclass) so
# a Mender artifact carries the kernel for both slots in lockstep.
UKI_ROOTFS_DIR=/usr/lib/mender
# Boot attempts the trial is granted before systemd-boot falls back.
UKI_TRIES=${MENDER_UKI_TRIES:-3}

# On-ESP names. The trial MUST sort before the committed image by id (see the
# selection-model note above): "uki-update" > "uki-current".
COMMITTED_UKI=uki-current.efi
TRIAL_PREFIX=uki-update

# ESP_LINUX_DIR is discovered at runtime by discover_esp(); see that function.
ESP_LINUX_DIR=

# systemd-boot scans <ESP>/EFI/Linux for UKIs. The ESP is mounted at BOTH
# /boot (from the wic) and /boot/efi (meta-mender's boot mountpoint), and on
# case-insensitive vfat the /boot/efi mount lands on the ESP's own "EFI"
# dentry -- so /boot/EFI is shadowed and /boot/EFI/Linux resolves to the
# nonexistent ESP:/Linux. Anchor on wherever the committed/trial UKIs actually
# live rather than assume a fixed path.
discover_esp() {
    for _d in /boot/efi/EFI/Linux /boot/EFI/EFI/Linux /boot/EFI/Linux; do
        if [ -e "$_d/$COMMITTED_UKI" ] || ls "$_d/$TRIAL_PREFIX"+*.efi >/dev/null 2>&1; then
            ESP_LINUX_DIR="$_d"; break
        fi
    done
    # Fall back to the meta-mender boot mountpoint, which gives an unshadowed
    # view of the ESP root, if nothing is present yet to anchor on.
    [ -n "$ESP_LINUX_DIR" ] || ESP_LINUX_DIR=/boot/efi/EFI/Linux
}

# ---- slot <-> name helpers ------------------------------------------------

# Map a mender_boot_part number to the per-slot UKI basename staged in the
# rootfs (the *source* the trial is copied from). The on-ESP name is generic
# (uki-update/uki-current); the rootfs the UKI boots is fixed by its baked
# root=PARTLABEL, not by the ESP filename.
src_uki_for_part() {
    case "$1" in
        2) echo "$UKI_ROOTFS_DIR/uki-a.efi" ;;
        3) echo "$UKI_ROOTFS_DIR/uki-b.efi" ;;
        *) return 1 ;;
    esac
}

part_for_label() {
    case "$1" in
        mender-rootfsa) echo 2 ;;
        mender-rootfsb) echo 3 ;;
        *) return 1 ;;
    esac
}

# Which slot did we ACTUALLY boot? From the baked-in root= of the running UKI,
# falling back to the PARTLABEL of the mounted root.
current_boot_part() {
    for _tok in $(cat /proc/cmdline 2>/dev/null || true); do
        case "$_tok" in
            root=PARTLABEL=*)
                if _p=$(part_for_label "${_tok#root=PARTLABEL=}"); then
                    echo "$_p"; return 0
                fi
                ;;
        esac
    done
    _label=$(findmnt -n -o PARTLABEL / 2>/dev/null || true)
    if [ -n "$_label" ] && _p=$(part_for_label "$_label"); then
        echo "$_p"; return 0
    fi
    return 1
}

# ---- persistent KEY=VALUE state -------------------------------------------

init_state() {
    if [ ! -f "$STATE_FILE" ]; then
        mkdir -p "$(dirname "$STATE_FILE")"
        # mender_boot_part is intentionally NOT seeded (always introspected).
        # The canaries are pre-seeded so the rootfs-image update module's
        # `set -e` canary check does not abort the install with exit-1.
        cat >"$STATE_FILE" <<EOF
upgrade_available=0
bootcount=0
trial_part=
mender_check_saveenv_canary=1
mender_saveenv_canary=1
EOF
    fi
}

read_var() {
    grep -E "^$1=" "$STATE_FILE" 2>/dev/null | head -n 1 | cut -d= -f2-
}

write_var() {
    _k=$1
    _v=$2
    _tmp=$(mktemp)
    grep -vE "^$_k=" "$STATE_FILE" >"$_tmp" 2>/dev/null || true
    printf '%s=%s\n' "$_k" "$_v" >>"$_tmp"
    mv "$_tmp" "$STATE_FILE"
}

# ---- ESP manipulation -----------------------------------------------------

# Stage the given (inactive) slot's UKI onto the ESP as the trial, with a
# tries counter, so systemd-boot will boot it (it sorts before uki-current)
# and auto-roll-back if it never gets blessed.
stage_trial() {
    _part=$1
    _src=$(src_uki_for_part "$_part") || {
        echo "mender-uki-shim: invalid mender_boot_part=$_part (expected 2 or 3)" >&2
        return 1
    }
    if [ ! -f "$_src" ]; then
        echo "mender-uki-shim: WARNING $_src missing; ESP not refreshed" >&2
        return 1
    fi
    mkdir -p "$ESP_LINUX_DIR"
    rm -f "$ESP_LINUX_DIR/$TRIAL_PREFIX"+*.efi
    cp -f "$_src" "$ESP_LINUX_DIR/$TRIAL_PREFIX+$UKI_TRIES.efi"
    sync
}

# Commit: promote the trial to the committed image (strip counter + rename),
# replacing the previous committed image.
promote_trial() {
    for _f in "$ESP_LINUX_DIR/$TRIAL_PREFIX"+*.efi; do
        [ -e "$_f" ] || continue
        rm -f "$ESP_LINUX_DIR/$COMMITTED_UKI"
        mv -f "$_f" "$ESP_LINUX_DIR/$COMMITTED_UKI"
    done
    sync
}

# Rollback finalisation: drop the (failed, bad) trial; keep uki-current.
discard_trial() {
    rm -f "$ESP_LINUX_DIR/$TRIAL_PREFIX"+*.efi
    sync
}

# upgrade_available -> 0 means Mender has finished a trial. If we are running
# on the slot we trialled, it booted healthy -> commit (promote). If we are
# back on the committed slot, systemd-boot rolled us back -> discard the trial.
finalize() {
    _tp=$(read_var trial_part)
    [ -n "$_tp" ] || return 0
    _running=$(current_boot_part 2>/dev/null || echo "")
    if [ -n "$_running" ] && [ "$_running" = "$_tp" ]; then
        promote_trial
    else
        discard_trial
    fi
    write_var trial_part ""
}

apply_var() {
    _key=$1
    _val=$2
    write_var "$_key" "$_val"
    case "$_key" in
        mender_boot_part)
            [ -n "$_val" ] || return 0
            _running=$(current_boot_part 2>/dev/null || echo "")
            if [ -n "$_running" ] && [ "$_val" = "$_running" ]; then
                # Targeting the running (committed) slot: not a new trial.
                discard_trial
                write_var trial_part ""
            else
                stage_trial "$_val"
                write_var trial_part "$_val"
            fi
            ;;
        upgrade_available)
            # NB: must be an `if`, not `[ ... ] && finalize`. The latter
            # evaluates to the (false) test status when _val != 0, which under
            # `set -e` -- and we run inside Mender's batch `fw_setenv -s -` loop
            # -- would abort the shim with exit 1 on every install (which sends
            # upgrade_available=1), failing ArtifactInstall.
            if [ "$_val" = "0" ]; then finalize; fi
            ;;
    esac
}

# ---- command dispatch -----------------------------------------------------

cmd=$(basename "$0")

case "$cmd" in
    fw_printenv)
        init_state
        if [ $# -eq 0 ]; then
            _p=$(current_boot_part 2>/dev/null || echo "")
            [ -n "$_p" ] && printf 'mender_boot_part=%s\n' "$_p"
            cat "$STATE_FILE"
        else
            case "$1" in
                mender_boot_part|mender_boot_part_hex)
                    _p=$(current_boot_part 2>/dev/null || echo "")
                    if [ -z "$_p" ]; then
                        echo "## Error: \"$1\" not defined" >&2
                        exit 1
                    fi
                    printf '%s=%s\n' "$1" "$_p"
                    ;;
                *)
                    _val=$(read_var "$1")
                    if [ -z "$_val" ]; then
                        echo "## Error: \"$1\" not defined" >&2
                        exit 1
                    fi
                    printf '%s=%s\n' "$1" "$_val"
                    ;;
            esac
        fi
        ;;
    fw_setenv)
        init_state
        discover_esp
        # Batch mode: `fw_setenv -s <file>` reads "<key> <value>" pairs from a
        # file (or stdin if file is "-"). Mender uses this to commit several
        # vars at once.
        if [ "$1" = "-s" ]; then
            _src=${2:--}
            if [ "$_src" = "-" ]; then
                _input=$(cat -)
            else
                _input=$(cat "$_src")
            fi
            printf '%s\n' "$_input" | while IFS= read -r _line; do
                case "$_line" in
                    ""|\#*) continue ;;
                esac
                case "$_line" in
                    *=*) _k=${_line%%=*}; _v=${_line#*=} ;;
                    *)   _k=${_line%% *}; _v=${_line#"$_k"}; _v=${_v# } ;;
                esac
                apply_var "$_k" "$_v"
            done
            exit 0
        fi
        if [ $# -eq 2 ]; then
            apply_var "$1" "$2"
        elif [ $# -eq 1 ]; then
            case "$1" in
                *=*) apply_var "${1%%=*}" "${1#*=}" ;;
                *)   apply_var "$1" "" ;;
            esac
        else
            echo "Usage: fw_setenv KEY VALUE | fw_setenv KEY=VALUE | fw_setenv -s FILE|-" >&2
            exit 1
        fi
        ;;
    mender-uki-shim)
        init_state
        _p=$(current_boot_part 2>/dev/null || echo "")
        [ -n "$_p" ] && printf 'mender_boot_part=%s\n' "$_p"
        cat "$STATE_FILE"
        ;;
    *)
        echo "mender-uki-shim: unknown invocation as $cmd" >&2
        exit 1
        ;;
esac
