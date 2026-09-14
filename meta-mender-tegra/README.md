# meta-mender-tegra

Mender integration layer for NVIDIA Tegra hardware.

The supported boards are:

- Thor
- AGX Orin
- Orin Nano
- Orin NX

meta-tegra's `wrynose` branch is L4T 39.2.0 (Jetpack 7) and carries machines for
tegra234 and tegra264 only. The Jetpack 4 and 5 era platforms (Nano, TX1, TX2,
Xavier) are not available here; use the `scarthgap` branch for those.

## Dependencies

These layers depend on:

```
URI: https://github.com/OE4T/meta-tegra.git
layers: meta-tegra
branch: wrynose
revision: HEAD
```

```
URI: https://github.com/mendersoftware/meta-mender.git
layers: meta-mender-core
branch: master
revision: HEAD
```

## Layer structure

A build takes three of these: the common layer, one update scheme, one Jetpack
release.

- `meta-mender-tegra-common`
  What both schemes need, across Jetpack releases: partition numbers, the storage
  device, the A/B slot size calculation, the flash layouts, the persistent
  machine-id, and the disk and ESP detection both schemes resolve their
  partitions with.

- `meta-mender-tegra-classic`
  The classic update scheme: Mender's stock `rootfs-image` update module, driven
  through this layer's state scripts and the `fw_printenv`/`fw_setenv` shims.

- `meta-mender-tegra-native`
  The Tegra-native update scheme: a `tegra-rootfs-image` update module driving
  `nvbootctrl`, the BSP partlabels and the UEFI capsule directly, with none of
  those adapters.

- `meta-mender-tegra-jetpack7`
  Jetpack 7 specific parts, matching the `wrynose` branch of `meta-tegra`.

### Selecting an update scheme

One scheme layer in `BBLAYERS`, its class in `INHERIT`:

```
BBLAYERS += "\
    ${TOPDIR}/../meta-mender-community/meta-mender-tegra/meta-mender-tegra-common \
    ${TOPDIR}/../meta-mender-community/meta-mender-tegra/meta-mender-tegra-classic \
    ${TOPDIR}/../meta-mender-community/meta-mender-tegra/meta-mender-tegra-jetpack7 \
"
INHERIT += "tegra-mender-classic"
```

For the native scheme, substitute `meta-mender-tegra-native` and
`INHERIT += "tegra-mender-native"`.

Two things are refused at parse time. Inheriting `tegra-mender-common` directly:
the scheme class pulls it in, and on its own it would configure no scheme at all.
And two scheme layers at once: the bbappends of both would apply whichever class
was inherited, yielding an image whose slot verification belongs to the other
scheme.

The schemes are mutually exclusive on the device as well. Neither can install the
other's artifact, so there is no migration path; see
[meta-mender-tegra-native/README.md](meta-mender-tegra-native/README.md).

## Quick start

See the mender hub pages and the documentation for the `tegrademo-mender`
distro on the [tegra-demo-distro](https://github.com/OE4T/tegra-demo-distro) repository
for the most up to date instructions on starting out with mender and tegra.

## [`kas`](https://github.com/siemens/kas) configurations

Build configs (kas) live in the companion
[mender-community-images](https://github.com/theyoctojester/mender-community-images)
repo, under `yocto/<release>/{tagged,floating}/tegra/jetpack<N>/<scheme>/`, where
the last directory is the update scheme the configuration selects:

```
git clone https://github.com/theyoctojester/mender-community-images
kas build mender-community-images/yocto/wrynose/tagged/tegra/jetpack7/classic/jetson-agx-thor-devkit.yml
```

Substitute `native/` for a configuration on the Tegra-native scheme. Not every
board carries one.

Jetpack 5 and 6 machines are covered by the `scarthgap` configurations in the
same repository.

### The data partition

Mender's persistent data does not go on `UDA`, the partition NVIDIA's layouts
provide for it. NVIDIA state that `UDA` is ["reserved by NV for OTA
process"](https://forums.developer.nvidia.com/t/jetson-orin-nx-custom-partition-layout-fails-with-uda-at-the-end/316401/6),
and the thread that answer comes from is someone moving `UDA` to the end of a
custom layout so it could grow, which fails.

So `tegra-storage-layout-base` appends a separate `permanet_user_storage`
partition to the machine's layout, after `APP_b` and marked fill-to-end
(`allocation_attribute 0x808`), and writes `DATAFILE` there. `UDA` is left
exactly as NVIDIA shipped it.

Three things follow from the partition being last and fill-to-end:

- `/data` takes whatever remains of the medium rather than 400 MiB. On a 64 GB
  card that is about 28 GiB.
- `mender-growfs-data` has nothing left to do, instead of failing every boot
  with `Error: Can't have overlapping partitions.` as it does when the data
  partition sits ahead of the rootfs slots.
- The medium is fully allocated. `make-sdcard`'s `find_finalpart` takes the
  first fill-to-end partition and only falls back to its `APP`/`APP_b` special
  case when there is none, which is what used to leave half a card unused.

No layouts are shipped by this layer. The partition is derived into whichever
layout the machine already selected, so machines with no configuration here are
covered on the same terms and an L4T bump needs no maintenance.

The partition number is not uniform, because it follows on from the highest id
the stock layout already uses: `p17` on both t234 layouts and `p13` on t264.
`MENDER_DATA_PART_NUMBER_DEFAULT` states it per family and `do_install` fails
the build if the two disagree, since that number lands in `/etc/fstab` and a
mismatch mounts the wrong device or none.

#### Keeping the old arrangement

`TEGRA_MENDER_DATA_PART_NAME = "UDA"` puts the data image back on `UDA`, which
is what every machine except `p3768-0000-p3767-0000` did previously. Nothing is
appended when the named partition already exists, and the data partition numbers
follow the same variable, so the two cannot be set inconsistently.

Existing fleets need this. The partition number is in `/etc/fstab` in the rootfs,
so a device flashed with its data on `UDA` that takes a rootfs update built for
the trailing partition mounts a partition that is not there. Moving a fleet
across means reflashing it, not updating it.

### Data partition size

`MENDER_DATA_PART_SIZE_MB` sizes the ext4 data image, and is written into the
layout as the data partition's size at `do_install` time so the two cannot
disagree.

On the default arrangement that size is only a floor, since the partition is
fill-to-end and grows past it. It is load-bearing on the `UDA` path above, where
the partition is fixed-size: without it, raising the variable produces an image
that no longer fits the 400 MiB the templates allocate.

Fit stays the integrator's responsibility either way: the A/B slots, the data
partition and the layout's fixed partitions must together fit the device, or
`tegraparser` aborts GPT generation.

`TEGRA_MENDER_UDA_SIZE_MB` is the former name for this and still works: it feeds
`TEGRA_MENDER_DATA_PART_SIZE_MB`, so a configuration written against it needs no
change. Setting either one empty skips the size rewrite and leaves the layout's
own size alone, which on the `UDA` path above means the template's 400 MiB.

## The classic update scheme

Mender's stock `rootfs-image` update module is written for u-boot and GRUB
systems. `meta-mender-tegra-classic` supplies the adapters it needs on Tegra:

| adapter | provides |
|---|---|
| `libubootenv-fake` | the `fw_printenv`/`fw_setenv` the module calls. `fw_printenv mender_boot_part` is answered from `nvbootctrl get-current-slot`, `fw_setenv upgrade_available` is kept in a flag file |
| `ArtifactInstall_Leave_50_switch-rootfs` | the slot switch. Mounts the freshly written slot read only to copy the UEFI capsule out of it |
| `ArtifactCommit_Leave_50_verify-slot` | `nvbootctrl verify` |
| `ArtifactRollback_Leave_50_abort-blupdate` | removal of the staged capsule on rollback |
| `mender-update-verifier` | reading `RootfsStatusSlot{A,B}` and clearing `upgrade_available` |
| `nv_update_verifier` | the wrapper meta-tegra's verifier unit runs, keying the verification window off `upgrade_available` |
| `RootfsPartA`/`RootfsPartB` in `mender.conf` | the rootfs partition names, which the BSP layout calls `APP` and `APP_b` |

This is the scheme every published Tegra build uses and the one verified on
hardware.

## The native update scheme

`meta-mender-tegra-native` replaces that stack with a single update module,
`tegra-rootfs-image`, calling the BSP directly: `nvbootctrl -t rootfs` for slot
state and verification, `/dev/disk/by-partlabel/APP{,_b}` for the partitions,
`mender-flash` for the write, the UEFI capsule for the switch. The capsule ships
inside the artifact, so nothing has to mount the freshly written slot.

The artifact keeps the canonical `.mender` name and still provides
`rootfs-image.version`, so the upload and the server side are unchanged. Only the
payload type inside differs; `mender-artifact read` tells the two apart.

Verification window, why `nv_update_verifier` is disabled rather than removed, and
the scheme's limitations:
[meta-mender-tegra-native/README.md](meta-mender-tegra-native/README.md).

## Shell portability

These layers install shell scripts onto the target: the Mender state scripts, the
`fw_printenv`/`fw_setenv` shims, the update verifiers and the machine-id helper.
They run on images such as `core-image-minimal`, where `/bin/sh` is busybox ash
and bash is not installed at all, so they must not use bash-only syntax.

busybox ash accepts more than POSIX does. `local`, `source`, `[[ ]]`, the
`function` keyword, `${var:offset:length}` and `${#var}` all work. What does not:

- herestrings (`<<<`)
- C-style `for (( ; ; ))` loops
- `var+=value` appending. This one is the dangerous case: ash parses it as a
  command name rather than an assignment, so it does not fail the script, it
  just leaves the variable empty.
- a `#!/bin/bash` interpreter line

Check a script before committing it:

```
busybox ash -n path/to/script
```

Note that this only catches parse errors. `var+=value` parses fine and fails at
runtime, so grep for it as well.

## Acknowlegements

Special thanks to [Matt Madison](https://github.com/madisongh) for his contributions to
support zeus and later branches and his work on meta-tegra which makes this mender
integration possible.

Thanks also to [Kurt Keifer](https://github.com/kekiefer/) for his contributions and
cleanup to support additional platforms and the tegra-demo-distro on the dunfell release.
