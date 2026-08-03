#!/bin/sh
# /init for the Tegra Mender recovery system.
#
# This runs entirely from RAM and never switch_roots. That is the whole point:
# both rootfs slots stay unmounted, so either of them can be rewritten.
#
# It brings up just enough to run the Mender client in managed mode against the
# device's own identity and state, which live on the data partition rather than
# in either rootfs. Mounting that one partition is what makes the recovery
# system the *same* device to the server, rather than a new one.
#
# Must parse and run under busybox ash. Do not use 'var+=' to append: ash parses
# that as a command name, so it fails silently and leaves the variable empty.
# /usr/local/sbin first, so the recovery reboot wrapper shadows busybox reboot
# for everything started from here, mender-update above all.
PATH=/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin
export PATH

MENDER_DATA_PART="@@MENDER_DATA_PART@@"
MENDER_DATA_PARTLABELS="@@MENDER_DATA_PARTLABELS@@"
ESP_PARTLABEL="esp"
L4T_BOOTMODE_VAR=/sys/firmware/efi/efivars/L4TDefaultBootMode-781e084c-a330-417c-b678-38e696380cb9

mount -t proc proc -o nosuid,nodev,noexec /proc
mount -t devtmpfs none -o nosuid /dev
mount -t sysfs sysfs -o nosuid,nodev,noexec /sys
mount -t tmpfs tmpfs /run 2>/dev/null
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts 2>/dev/null
mkdir -p /sys/firmware/efi/efivars 2>/dev/null
mount -t efivarfs efivarfs -o nosuid,nodev,noexec /sys/firmware/efi/efivars 2>/dev/null

# /var/log is a symlink to volatile/log in an OE rootfs, and nothing mounts
# /var/volatile here, so the target has to exist or every redirect into /var/log
# fails. That is not cosmetic: it is what stopped mender-auth and mender-update
# from starting, because their output redirection failed before they ran.
mkdir -p /var/volatile/log /var/volatile/tmp /var/lib /etc 2>/dev/null

# An ssh session does not inherit this script's PATH; dropbear gives the login
# shell its own. Without this an operator who types `reboot` gets busybox's,
# which asks PID 1 to bring the system down and silently does nothing, because
# PID 1 here is this script. Put the same PATH in /etc/profile so an interactive
# session finds the wrapper too.
printf 'PATH=%s\nexport PATH\n' "/usr/local/sbin:/sbin:/bin:/usr/sbin:/usr/bin" > /etc/profile 2>/dev/null

# ...and belt and braces, point every reboot on the filesystem at the wrapper.
# /etc/profile only covers a login shell, and `ssh host reboot` is neither login
# nor interactive: dropbear hands it a default PATH and it finds busybox's
# reboot, which asks PID 1 to bring the system down and silently does nothing.
# Replacing the binaries themselves means it cannot matter which PATH the caller
# happens to have.
for _rb in /sbin/reboot /usr/sbin/reboot /bin/reboot /usr/bin/reboot; do
    [ -e "$_rb" ] && ln -sf /usr/local/sbin/reboot "$_rb" 2>/dev/null
done

# Loopback. mender-auth runs a local HTTP proxy that mender-update talks to, and
# it cannot bind 127.0.0.1 on an interface that is still down. An initramfs
# starts with lo down, so nothing else brings it up.
ip link set lo up 2>/dev/null

# Pin every stream to the real console. The kernel hands PID 1 whichever
# console= came last on the command line, and a Tegra normally has two
# (ttyTCU0 and tty0), so trusting the default puts all of this on the HDMI
# framebuffer where the bench cannot see it.
CONSOLE=/dev/console
for c in /dev/ttyTCU0 /dev/ttyS0 /dev/console; do
    if [ -c "$c" ]; then CONSOLE="$c"; break; fi
done
# Prove the console can actually be opened before exec'ing onto it. `exec` is a
# POSIX special builtin, so a redirection error here would exit this shell, and
# this shell is PID 1: the kernel would panic with "Attempted to kill init"
# before printing anything that explains why. Testing it in a subshell first
# costs one fork and cannot take PID 1 with it.
if ( exec >"$CONSOLE" 2>&1 <"$CONSOLE" ) 2>/dev/null; then
    exec >"$CONSOLE" 2>&1 <"$CONSOLE"  # lint-ok: special-redirect (guarded above)
fi

say() { echo "[recovery] $*"; }

echo
echo "==============================================="
echo "  Tegra Mender recovery system"
echo "  built @@RECOVERY_STAMP@@"
echo "==============================================="

# L4TDefaultBootMode is non-volatile, so a board told to boot recovery keeps
# booting recovery. Stand it down immediately, so that reaching this point
# always leaves the board booting normally on the next reset. Re-arming is then
# a deliberate act. Note this is also what makes a *failed* recovery boot
# survivable: the variable is already back to normal before anything else here
# can go wrong.
if [ -f "$L4T_BOOTMODE_VAR" ]; then
    chattr -i "$L4T_BOOTMODE_VAR" 2>/dev/null
    if printf '\007\000\000\000\001\000\000\000' > "$L4T_BOOTMODE_VAR" 2>/dev/null; then
        say "L4TDefaultBootMode reset to 1; the next reset boots normally"
    else
        say "WARNING: could not reset L4TDefaultBootMode"
    fi
else
    say "WARNING: L4TDefaultBootMode efivar not present"
fi

say "loading modules"
find /sys -name modalias | while read -r m; do
    modprobe -q "$(cat "$m")" 2>/dev/null
done
for mod in nvme r8168 r8169 uas; do
    modprobe -q "$mod" 2>/dev/null
done

# Resolve a GPT partition label to a device node. There is no udev here, so
# /dev/disk/by-partlabel does not exist and the symlink the update modules
# normally rely on is simply absent.
resolve_partlabel() {
    _want="$1"
    if [ -e "/dev/disk/by-partlabel/$_want" ]; then
        readlink -f "/dev/disk/by-partlabel/$_want"
        return 0
    fi
    _dev=$(lsblk -n -r -o NAME,PARTLABEL 2>/dev/null \
           | awk -v w="$_want" '$2 == w { print "/dev/" $1; exit }')
    [ -n "$_dev" ] || _dev=$(blkid -t "PARTLABEL=$_want" -o device 2>/dev/null | head -n 1)
    [ -n "$_dev" ] || return 1
    echo "$_dev"
}

wait_for_block() {
    _n=0
    while [ "$_n" -lt 30 ]; do
        [ -b "$1" ] && return 0
        sleep 0.5
        _n=$((_n + 1))
    done
    return 1
}

# The data partition. Prefer the device path the build computed, because a
# machine may relabel or renumber it; fall back to the labels the Tegra layouts
# actually use.
DATA_DEV=""
if [ -n "$MENDER_DATA_PART" ] && wait_for_block "$MENDER_DATA_PART"; then
    DATA_DEV="$MENDER_DATA_PART"
else
    for lbl in $MENDER_DATA_PARTLABELS; do
        DATA_DEV=$(resolve_partlabel "$lbl") && [ -n "$DATA_DEV" ] && break
        DATA_DEV=""
    done
fi

MENDER_READY=0
if [ -z "$DATA_DEV" ]; then
    say "ERROR: cannot find the Mender data partition; the client cannot run"
else
    say "data partition is $DATA_DEV"
    mkdir -p /data
    # A recovery boot often follows something unpleasant, so do not assume the
    # data filesystem was unmounted cleanly.
    e2fsck -p "$DATA_DEV" >/dev/null 2>&1
    _fsck_rc=$?
    # 0 = clean, 1 = errors corrected. Anything above that needs a human.
    if [ "$_fsck_rc" -gt 1 ]; then
        say "WARNING: e2fsck on $DATA_DEV returned $_fsck_rc"
    fi
    if mount -t ext4 "$DATA_DEV" /data; then
        say "mounted $DATA_DEV at /data"
        mkdir -p /data/mender
        rm -rf /var/lib/mender
        mkdir -p /var/lib
        ln -sf /data/mender /var/lib/mender
        MENDER_READY=1
    else
        say "ERROR: could not mount $DATA_DEV at /data"
    fi
fi

# The ESP, because the update module stages the UEFI capsule there and the
# capsule is what switches the boot chain.
ESP_DEV=$(resolve_partlabel "$ESP_PARTLABEL")
if [ -n "$ESP_DEV" ]; then
    mkdir -p /boot/efi
    if mount -t vfat "$ESP_DEV" /boot/efi; then
        say "mounted $ESP_DEV at /boot/efi"
    else
        say "WARNING: could not mount the ESP at /boot/efi; updates will fail"
    fi
else
    say "WARNING: no esp partition found; updates will fail"
fi

# TLS to the Mender server needs a plausible clock, and getting one here is
# harder than it looks.
#
# The Jetson devkits have two RTCs, nvvrs-pseq-rtc and tegra_rtc, and on the
# Orin NX neither survives a power cycle: the full system also boots at 1970 and
# only becomes correct once systemd-timesyncd has run. So there is nothing to
# read the time from at this point, and every server certificate looks "not yet
# valid" until something fixes it.
#
# Note there is deliberately no build-date fallback. SOURCE_DATE_EPOCH, the only
# build timestamp available, is pinned to 2011 by the reproducible-builds
# machinery, so seeding from it would move the clock further into the past and
# hide the problem behind the same TLS error.
SANE_EPOCH=1700000000      # ~Nov 2023; anything earlier cannot be real here
NTP_SERVERS="@@NTP_SERVERS@@"

clock_now() { date +%s 2>/dev/null || echo 0; }

# 1. Any RTC that happens to be battery-backed. Free, and correct where it works.
if [ "$(clock_now)" -lt "$SANE_EPOCH" ]; then
    for r in /dev/rtc0 /dev/rtc1 /dev/rtc; do
        [ -e "$r" ] || continue
        hwclock -s -f "$r" 2>/dev/null || continue
        if [ "$(clock_now)" -ge "$SANE_EPOCH" ]; then
            say "clock set from $r: $(date -u)"
            break
        fi
    done
fi

# 2. The data partition's own timestamps. Not the real time, but a genuine lower
#    bound: the device cannot have written those files in the future. This is
#    what makes the recovery system usable with no network time at all, and in
#    practice it lands inside the validity window of a certificate that was
#    working the last time the device ran.
if [ "$(clock_now)" -lt "$SANE_EPOCH" ] && [ "$MENDER_READY" = 1 ]; then
    newest=0
    for f in /data/mender/mender-store /data/mender/mender.conf \
             /data/mender/mender-agent.pem /data/mender /data; do
        [ -e "$f" ] || continue
        t=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        [ "$t" -gt "$newest" ] && newest="$t"
    done
    if [ "$newest" -ge "$SANE_EPOCH" ]; then
        date -s "@${newest}" >/dev/null 2>&1
        say "clock seeded from the data partition: $(date -u)"
        say "         (a lower bound, not the real time)"
    fi
fi

# 3. Real time, if the network can supply it. Runs after the seed above so that
#    a one-shot chronyd has a plausible starting point, and after the network is
#    up, so it is deferred until then.
sync_clock_ntp() {
    command -v chronyd >/dev/null 2>&1 || return 1
    [ -n "$NTP_SERVERS" ] || return 1
    _args=""
    for s in $NTP_SERVERS; do _args="$_args server $s iburst"; done
    # -q: set the clock once and exit. -t: give up rather than hang the boot.
    chronyd -q -t 15 "$_args" >/dev/null 2>&1 || return 1
    return 0
}

say "bringing up the network"
_n=0
while [ "$_n" -lt 15 ]; do
    ip link show eth0 >/dev/null 2>&1 && break
    sleep 1
    _n=$((_n + 1))
done
if ip link show eth0 >/dev/null 2>&1; then
    ip link set eth0 up
    if udhcpc -i eth0 -q -n -t 8 -T 2 >/dev/null 2>&1; then
        say "$(ip -4 addr show eth0 | grep -o 'inet [0-9.]*')"
    else
        say "WARNING: DHCP failed on eth0; the client cannot reach the server"
    fi
else
    say "WARNING: no eth0"
fi

# Now that there is a network, try for the real time. Step 2 above only produced
# a lower bound.
if sync_clock_ntp; then
    say "clock synchronised over NTP: $(date -u)"
fi
if [ "$(clock_now)" -lt "$SANE_EPOCH" ]; then
    say "WARNING: the clock reads $(date -u) and nothing could correct it."
    say "         TLS to the server will fail certificate validation. Set it by"
    say "         hand with 'date -s \"YYYY-MM-DD HH:MM:SS\"', then run"
    say "         'mender-recovery-start-client'."
else
    say "clock reads $(date -u)"
fi

# Remote console. This is deliberately permissive and deliberately switchable.
#
# The trade-off: a device that has lost both rootfs slots has no other way in
# except a serial cable, and the whole point of this system is to avoid needing
# physical access. Against that, it is passwordless root over the network, on a
# system that can rewrite both rootfs slots. It is on by default because a
# recovery system nobody can reach is not a recovery system, and it is only ever
# running when the device has already failed. Turn it off with
# TEGRA_MENDER_RECOVERY_SSH = "0" if that trade is wrong for your deployment;
# the Mender client still works, so a device can still be repaired by a
# deployment, just not driven by hand.
start_remote_console() {
    if [ -f /etc/shadow ]; then
        sed -i 's|^root:[^:]*:|root::|' /etc/shadow
    elif [ -f /etc/passwd ]; then
        sed -i 's|^root:[^:]*:|root::|' /etc/passwd
    fi
    mkdir -p /etc/dropbear /var/run 2>/dev/null
    # /var/log is usually a symlink into /var/volatile, which does not exist in
    # this initramfs, so creating it can fail. That must not be fatal, and in
    # particular it must not be written with `: > file`: `:` is a POSIX *special*
    # builtin, and a redirection error on one exits a non-interactive shell. This
    # shell is PID 1, so that exit is a kernel panic. touch is an ordinary
    # command whose failure is just a non-zero status.
    mkdir -p /var/log 2>/dev/null || true
    touch /var/log/lastlog 2>/dev/null || true
    if command -v dropbear >/dev/null 2>&1; then
        dropbear -B -R -E -p 22 >/dev/null 2>&1 \
            && say "dropbear listening on 22 (root, blank password)" \
            || say "WARNING: dropbear failed to start"
    else
        say "WARNING: no dropbear in this image; console access only"
    fi
}

if [ "@@RECOVERY_SSH@@" = "1" ]; then
    start_remote_console
else
    say "remote console disabled at build time (TEGRA_MENDER_RECOVERY_SSH=0)"
fi

# The Mender client. Factored into its own script so an operator can restart it
# after fixing a clock, a data partition or a server configuration.
if [ "$MENDER_READY" = 1 ]; then
    mender-recovery-start-client || say "the client did not start; see above"
else
    say "the Mender client was NOT started, because /data is not available"
    say "repair the data partition, then run: mender-recovery-start-client"
fi

echo
say "'tegra-recovery help' lists the manual recovery commands"
echo

# Never exec the shell. If PID 1 exits the kernel panics with "Attempted to kill
# init", which on a recovery image takes the console with it. Respawn instead.
# busybox here is built without CONFIG_CTTYHACK, so there is no controlling
# terminal and therefore no job control in this shell.
while true; do
    /bin/sh <"$CONSOLE" >"$CONSOLE" 2>&1
    echo "[recovery] shell exited; respawning." >"$CONSOLE"
    sleep 1
done
