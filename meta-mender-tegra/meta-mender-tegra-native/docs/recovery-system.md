# The Tegra recovery system

`TEGRA_MENDER_RECOVERY = "1"` builds a RAM-only Mender-capable system into the
`recovery` partition. This is the detail behind the summary in ../README.md.

## Building it

Select the native scheme, which this needs, and turn the recovery system on:

```
INHERIT += "tegra-mender-native"
TEGRA_MENDER_RECOVERY = "1"
```

Then build the image as usual. Three extra things appear in the deploy
directory:

| | |
|---|---|
| `tegra-mender-recovery-initramfs-<machine>.cpio.gz` | the recovery system itself |
| `tegra-mender-recovery.img` | that plus the kernel, in the Android boot image format L4TLauncher reads |
| the flash package | now contains `tegra-mender-recovery.img`, and the external layout names it in the `recovery` partition |

Flashing the resulting package populates the partition. To put it on a board
that is already running, without a reflash, write it straight to the partition:

```sh
dd if=tegra-mender-recovery.img of=/dev/disk/by-partlabel/recovery bs=1M
sync
```

Note the credentials only reach the data partition when the *data image* is
flashed, so a board updated rather than reflashed needs
`/data/mender/mender.conf` populated by hand. See "Credentials" below.

## Configuration variables

| variable | default | what it does |
|---|---|---|
| `TEGRA_MENDER_RECOVERY` | `0` | the opt-in. Only exists in this layer, so it cannot be set without the native scheme. |
| `TEGRA_RECOVERY_KERNEL_PART_SIZE` | `83886080` | size of the `recovery` partition, and the ceiling the build checks against. Raising it changes the flash layout and needs a reflash. Set globally in `tegra-mender-native.bbclass` so recipes that do not inherit meta-tegra's image class can see it. |
| `TEGRA_MENDER_RECOVERY_INSTALL` | empty | extra packages for the recovery system. |
| `TEGRA_MENDER_RECOVERY_NETDRV` | `nv-kernel-module-r8168` | the network driver. Must be named explicitly; see below. Override on boards with a different NIC. |
| `TEGRA_MENDER_RECOVERY_SSH` | `1` | sshd with a blank root password in the recovery system. See the security note below before leaving it on. |
| `TEGRA_MENDER_RECOVERY_NTP_SERVERS` | `pool.ntp.org` | tried once with `chronyd -q` after the network is up. Set to what a closed network can reach, or empty to skip. |
| `TEGRA_MENDER_DATA_PARTLABELS` | `UDA permanet_user_storage` | partition labels to look for if the build-time device path does not appear. Both spellings the Tegra layouts use, NVIDIA's typo included. |
| `TEGRA_MENDER_RECOVERY_CMDLINE` | `console=tty0 fbcon=map:0 video=efifb:off console=ttyTCU0,115200` | kernel command line baked into the boot image. Keep the serial console **last**; see below. |
| `TEGRA_MENDER_RECOVERY_IMAGE` | `tegra-mender-recovery-initramfs` | the image recipe packed into the boot image. |
| `TEGRA_MENDER_RECOVERY_BOOTIMG` | `tegra-mender-recovery.img` | filename of the boot image, in the deploy directory and in the flash layout. |
| `TEGRA_MENDER_RECOVERY_SKIP_IMAGES` | `tegra-mender-recovery-initramfs initramfs espimage` | image recipes the staging class must not attach itself to. Without the first entry the recovery initramfs would depend on the boot image that depends on it. |

## Why the partition is already there

meta-tegra creates `recovery` and `recovery-dtb` (and `recovery_alt`,
`recovery-dtb_alt` on redundant layouts) on 34 of the 37 t234 flash layouts that
ship with L4T 39.2.0. The three exceptions are `flash_t234_qspi.xml` and its
`_industrial` and `_safety` siblings, which are the QSPI-only layouts used when
the rootfs is external; there the recovery partition lives in the external
layout instead. The t264 layouts carry it too.

Then it leaves them empty. `image_types_tegra.bbclass:297` substitutes `RECNAME`
to `recovery` and sizes it from `TEGRA_RECOVERY_KERNEL_PART_SIZE`, and line 298
does `-e"/RECFILE/d" -e"/RECDTB-FILE/d"`, deleting the lines that would give the
partitions content. So the space is reserved on every build and never used.

`recovery_alt` is unreachable regardless. `FindPartitionInfo`
(`L4TLauncher.c:378`) matches either an exact partition name or a two-character
`_a` / `_b` suffix, and `_alt` is neither, so it is never selected for either
boot chain. One image in `recovery` serves both chains.

## When the firmware boots it

Two pieces of state, read by different predicates:

- `IsRootfsSlotBootable()` reads **only the retry count**, which lives in a
  hardware scratch register, not in a UEFI variable.
- `IsValidRootfs()` reads **only the `RootfsStatusSlot{A,B}` UEFI variables**
  (`0x00` normal, `0xFF` unbootable).

`ValidateRootfsStatus` then, for `NVIDIA_OS_REDUNDANCY_BOOT_ROOTFS`:

1. both status variables already unbootable, boot recovery at once and clear the
   scratch register;
2. current slot has retries left, decrement and boot it;
3. current slot at zero, flag it unbootable and check the other slot; if that
   has retries, switch to it and decrement;
4. other slot also at zero, flag it unbootable too and boot recovery.

Retry counts are restored only when the OS runs `nvbootctrl verify`, which under
Mender is the commit. `RootfsRetryCountMax` is 1 on the boards tested, so each
slot gets one uncommitted attempt, and recovery is reached once both have failed
once. That is the ordinary A/B exhaustion path, not an exotic one.

One wrinkle. A rootfs that is corrupt but still flagged normal with retries left
does not reach recovery on the first attempt: L4TLauncher fails to read
`extlinux.conf`, falls back to `BOOTMODE_BOOTIMG`, finds nothing in the kernel
partition, and cold resets. Since the retry count is decremented before each
attempt the counter still drains, so it converges on recovery after a few
resets, but it is a reset loop first.

Forcing it by hand, from a running system:

```sh
V=/sys/firmware/efi/efivars/L4TDefaultBootMode-781e084c-a330-417c-b678-38e696380cb9
chattr -i "$V"
printf '\007\000\000\000\003\000\000\000' > "$V"   # 3 = NVIDIA_L4T_BOOTMODE_RECOVERY
```

`\007` is the attribute word (non-volatile, boot service, runtime access), and
the payload follows. Value `1` is the normal extlinux boot.

The variable is non-volatile, so the recovery system resets it to `1` as one of
the first things its init does. Reaching the recovery system therefore always
leaves the board booting normally on the next reset, and arming another recovery
boot is a deliberate act. If a recovery boot ever fails outright, the UEFI setup
menu is reachable over the serial console: Device Manager, NVIDIA Configuration,
L4T Configuration, `L4T Boot Mode`.

## What the recovery system is

An initramfs that never `switch_root`s, so `/` is a ramdisk and neither rootfs
slot is mounted. Its init:

- picks a console explicitly, because the kernel makes the **last** `console=`
  `/dev/console` and a Tegra normally carries two;
- resets `L4TDefaultBootMode`, as above;
- loads the NVMe and network modules;
- mounts the Mender data partition at `/data` and points `/var/lib/mender` at
  `/data/mender`;
- mounts the ESP at `/boot/efi`, because the update module stages the capsule
  there;
- brings up the network and, unless `TEGRA_MENDER_RECOVERY_SSH = "0"`, starts
  sshd with a blank root password;
- starts `dbus-daemon --system`, then `mender-auth daemon`, then
  `mender-update daemon`.

Mounting the data partition is what makes this the *same device*. The device
key, `device_type`, the state database and the module payload directories all
live there, so the client authenticates as the device it has always been, and
the deployment state survives the reboot into the repaired slot.

Starting the two Mender daemons by hand is equivalent to what systemd does:
`mender-authd` is `Type=dbus` and `mender-updated` is `Type=idle`, and neither
uses `sd_notify`. That startup lives in `mender-recovery-start-client` rather
than inline in the init, so an operator can run it again after fixing whatever
stopped it the first time.

### A word about the remote console

The recovery system starts sshd with a blank root password by default. That is
worth being explicit about rather than burying, because it is passwordless root
over the network on a system that can rewrite both rootfs slots.

The reasoning: a device that has lost both slots has no other way in except a
serial cable, and not needing physical access is the entire point of building
this. The exposure is bounded in a way a normal system's is not, since the
recovery system only exists in RAM, only while the device has already failed,
and disappears on the next reset. It is still a real exposure on a shared
network.

Set `TEGRA_MENDER_RECOVERY_SSH = "0"` where that trade is wrong. The Mender
client is unaffected: a device can still be repaired by a deployment pushed from
the server, you just cannot drive it by hand over the network. If you want
key-based access instead, that is a small change to the init and a good idea for
anything past a lab.

### Four things that are easy to get wrong here

**`reboot` does not work in an initramfs, and fails silently.** mender-update
ends `ArtifactInstall` by running `reboot` and then waiting for the system to
come back. The ordinary busybox `reboot` asks PID 1 to bring the system down,
and PID 1 here is the recovery init, a shell script with no idea what that
request means. Nothing happens: the capsule stays staged and the deployment
waits for a restart that never comes. The image therefore ships
`/usr/local/sbin/reboot`, which the init puts at the front of `PATH` so it
shadows busybox without fighting the alternatives system over `/sbin/reboot`.
It flushes the ESP by unmounting it, which matters because the capsule that
performs the slot switch was just written there, and then calls
`busybox reboot -f`.

**Loopback has to be brought up explicitly.** `mender-auth` runs a local HTTP
proxy that `mender-update` connects to, and it cannot bind `127.0.0.1` while
`lo` is down, which is how an initramfs starts. The symptom is a single line in
the auth log, `Unable to start a local HTTP proxy: Cannot assign requested
address`, and everything else looks healthy.

**`/var/log` is a symlink into `/var/volatile`, whose target does not exist.**
Nothing mounts `/var/volatile` here, so every redirect into `/var/log` fails.
That is not cosmetic: it is what stopped both Mender daemons from starting,
because their output redirection failed before they ran. The init creates
`/var/volatile/log` early, and `mender-recovery-start-client` proves the
directory is writable and falls back to `/tmp` rather than losing the client to
a logging problem.

**The network driver has to be named explicitly.**
`TEGRA_MENDER_RECOVERY_NETDRV` defaults to `nv-kernel-module-r8168`, which is
what the p3768 carrier needs. meta-tegra does list the driver, in
`MACHINE_EXTRA_RRECOMMENDS`, but only `packagegroup-base` consumes that variable
and this image does not pull it in. The name meta-tegra uses there,
`kernel-module-r8168`, is an `RPROVIDES` and does not resolve from
`PACKAGE_INSTALL` unless the providing recipe is built, so the real package name
is required. Boards with a different NIC must override the variable. A recovery
system without a network is only half a recovery system, so this is worth
checking on a new board rather than discovering on the bench.

**The clock has to be plausible before the client starts, and this is harder
than it looks.** If the clock is wrong, every server certificate looks "not yet
valid" and the client fails with an opaque TLS error.

An Orin NX has two RTCs, `nvvrs-pseq-rtc` and `tegra_rtc`, and measured on the
bench, **neither survives a power cycle**. The full system also comes up at 1970
and only becomes correct once `systemd-timesyncd` has run. So there is nothing
to read the time from. Reading an RTC while the device is running is misleading:
`CONFIG_RTC_SYSTOHC` writes the NTP-corrected time back to it, so it looks
battery-backed right up until you pull the power.

The init therefore tries three things in order:

1. **Each RTC.** Free, and correct on a board that does have a backed one.
2. **The data partition's timestamps.** Not the real time, but a genuine lower
   bound: the device cannot have written those files in the future. This is what
   makes the recovery system usable with no network time at all, and in practice
   it lands inside the validity window of a certificate that was working the
   last time the device ran.
3. **`chronyd -q`**, once the network is up, against
   `TEGRA_MENDER_RECOVERY_NTP_SERVERS` (default `pool.ntp.org`). Set that to
   whatever a closed network can actually reach, or empty to skip it.

There is deliberately no build-date fallback. `SOURCE_DATE_EPOCH`, the only
build timestamp available, is pinned to 2011 by the reproducible-builds
machinery, so seeding from it would move the clock further into the past and
hide the problem behind the same TLS error. If nothing works the init says so
and prints the `date -s` command to fix it by hand.

## Credentials

`ServerURL` and `TenantToken` are moved into `/data/mender/mender.conf`, using
meta-mender's own mechanism:

```
MENDER_CONFIGURATION_VARS:append = " TenantToken"
MENDER_PERSISTENT_CONFIGURATION_VARS:append = " ServerURL TenantToken"
```

Both lines are needed. `mender-client-cpp.inc` filters the persistent list
against `MENDER_CONFIGURATION_VARS`, and `TenantToken` is not in meta-mender's
default allowlist, so adding it only to the persistent list silently does
nothing.

This *moves* the keys rather than copying them: migrated keys are deleted from
the transient config, so they no longer appear in `/etc/mender/mender.conf`.
Good for the rootfs image, which stops carrying the tenant token. Bad for a
device flashed before the change, which has no persistent `ServerURL` and would
lose its server on an update to an image built after it. Flash-time only.

## What the update module does differently

The same `tegra-rootfs-image` module ships in both the rootfs and the recovery
system, and switches on `/etc/tegra-mender-recovery`, a marker file only the
recovery image installs. Nothing is inferred from a lookup that failed.

| | rootfs context | recovery context |
|---|---|---|
| active slot | `nvbootctrl -t rootfs get-current-slot`, must match `/` | same, cross-checked against `BootChainOsCurrent` |
| `/` | must be the active slot | must be **neither** slot |
| slot devices | partlabel symlinks | partlabel, then `lsblk`, then `blkid`, then `RootfsPartA/B` |
| rollback | leaves the target's flag alone | re-flags the target unbootable |
| commit | `nvbootctrl verify` | refused |
| `tegra-rootfs-verify` | keeps the running slot good | refuses |

Three of those deserve a note.

**There is no udev in an initramfs**, so `/dev/disk/by-partlabel` does not exist
and the symlink the module normally resolves is simply absent. The fallback
chain ends at `RootfsPartA`/`RootfsPartB` in the persistent configuration, which
is on the data partition the recovery system has already mounted.

**Rollback must re-flag the target.** `ArtifactInstall` clears the target's
unbootable flag so the firmware will accept it after the switch. If the
deployment then fails while still in recovery, that switch never happened and
the target holds a torn filesystem. A device in recovery usually got there
because the other slot is unbootable too, so a target left flagged bootable is
what the firmware would boot next. In the rootfs context the flag is
deliberately left alone, because the device is running from the other slot.

**Commit is refused.** Committing asserts that the slot you are running from
works, and nothing has booted the new slot yet. An install started in recovery
is committed after the reboot, by the client in the slot it just wrote, using
the shared state database on the data partition.

`tegra-rootfs-verify` refuses for the same reason, and this is not academic. It
ships in the same package as the update module, so it is present in the recovery
image even though there is no systemd to run its unit. Left unguarded, running
it there would mark the boot chain's slot good and restore its retry count, and
the usual reason for being in recovery is that both slots ran out of retries: it
would undo the condition that produced the recovery boot and turn a clean
recovery into a boot loop.

## Size

The partition is 80 MiB and the build fails if the image does not fit, warning
once it passes 85%. Measured on an Orin NX 8GB:

| | bytes |
|---|---|
| kernel `Image` | 43,833,856 |
| recovery initramfs `cpio.gz` | ~17,000,000 |
| resulting boot image | ~60,800,000 (72%) |

The kernel dominates. Levers, cheapest first:

1. `BAD_RECOMMENDATIONS`. The image already drops `tegra-uefi-capsules`, worth
   about 11 MB, because the native update module takes its capsule from the
   artifact payload and never reads the installed copy. Only the legacy
   `switch-rootfs` state script reads that, which is why the capsule is a hard
   dependency under the legacy scheme and a recommendation under the native one.
2. Trim `TEGRA_MENDER_RECOVERY_INSTALL`, and anything a product added.
3. `CONFIG_EFI_ZBOOT`, currently off. It would take the kernel contribution to
   roughly the size of `Image.gz`, around 16 MB. Note this changes
   `KERNEL_IMAGETYPE` and therefore the normal boot path too, so it is not a
   local change.
4. Raise `TEGRA_RECOVERY_KERNEL_PART_SIZE`, set in `tegra-mender-native.bbclass`.
   This changes the flash layout, so it needs a full reflash, and it eats into
   the medium's budget: on the SD layouts the total is already 31,626,400,256
   bytes against 31,914,983,424 on a nominal 32 GB card.

## Manual fallback

`tegra-recovery` is in the image for when the client cannot run at all, for
instance if the data partition is too damaged to mount. It consumes a Mender
artifact directly, with busybox `tar` and `dd`, and needs no server:

```
tegra-recovery status
tegra-recovery install <slot> <artifact.mender>
tegra-recovery activate <slot>
tegra-recovery reset-slots
tegra-recovery mark <slot> normal|unbootable
tegra-recovery arm | disarm
```

It reads the payload member names out of the artifact's `manifest` rather than
listing the payload container, which would mean decompressing the whole rootfs
once just to learn what is in it. It also takes only the rootfs from a
Tegra-native artifact and ignores `tegra-bl.cap`, because applying a capsule
flips the bootloader chain and repairing a rootfs is not an update.

## What has been verified, and what has not

Verified on a Jetson Orin NX 8GB (`p3768-0000-p3767-0001`, NVMe, JetPack 7 /
L4T 39.2.0), 2026-07-30, and again on 2026-08-03 after this was carved into
`meta-mender-tegra-native`:

| | |
|---|---|
| recovery boots and the client authenticates as the same device | yes |
| deployment from recovery, slot A active, installs to B | yes, committed after the reboot |
| deployment from recovery, slot B active, installs to A | yes, fully unattended |
| both slots flagged unbootable, firmware selects recovery unaided, then a deployment repairs a slot | yes |
| deployment from recovery made to fail after `ArtifactInstall` | rolls back, re-flags the target unbootable |
| ordinary rootfs-context deployment, as a regression check | unchanged |
| offline harness | 67 assertions, under ash, dash and bash |
| flashed by RCM, then booted and updated over the air | yes, `recovery` populated byte for byte |

Not verified, and worth knowing before relying on any of it:

**Flash-time population is verified, on one machine.** An RCM flash of the
p3768-0000-p3767-0001 package wrote `tegra-mender-recovery.img` to the `recovery`
partition, and the md5 of the partition afterwards equalled the built image. The
internal QSPI layout is correctly left alone, because it has no such partition.
The board then booted and took an over-the-air update, so flash, boot and update
are covered as one chain.

Machines that use a layout **this layer** supplies rather than one of NVIDIA's, so
far only the 16GB Orin NX, needed a second rewrite pass to get the same entry: see
`TEGRA_MENDER_LAYOUT_FILENAMES_EXTRA` in
`meta-mender-tegra-common/recipes-bsp/tegra-binaries/tegra-mender-layout.inc`.
Without it the build was green, the boot image was in the flash package, and the
partition was left empty, because our own XML carries NVIDIA's `RECFILE`
placeholder and `image_types_tegra.bbclass` deletes every line that still has one.
That is fixed and checked in the generated layout for both Orin NX modules, but
only the 8GB one has actually been flashed.

**Secure Boot is off.** `tegra-mender-recovery-bootimg.bb` signs the boot image
with the BSP's own helper when `TEGRA_UEFI_USE_SIGNED_FILES` is true, because
`ReadAndroidStyleKernelPartition` verifies it when `IsSecureBootEnabled()`, but
that path has never run.

**One board, one layout.** NVMe on an Orin NX. The SD and eMMC layouts also
carry a `recovery` partition and should behave the same, but have not been
tried. `TEGRA_MENDER_RECOVERY_NETDRV` in particular is a p3768 default.

**The clock strategy is best-effort.** On a board with no usable RTC and no
reachable NTP server, the seed taken from the data partition's timestamps is a
lower bound, not the time. It is enough for a certificate that was valid when
the device last ran, and not enough for one issued since.
