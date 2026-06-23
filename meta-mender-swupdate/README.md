# meta-mender-swupdate

Manage a [SWUpdate](https://sbabic.github.io/swupdate/)-updated A/B system from
the Mender server, on `qemuarm64` (wrynose). SWUpdate stays the on-device
installer; the Mender client runs in client-only mode and a custom **`swu`
Update Module** installs a SWUpdate `.swu` image delivered inside a Mender
Artifact.

This is the classic *brownfield retrofit*: a product already using SWUpdate
gains Mender's fleet deployment, monitoring and remote access without changing
its on-device update mechanism.

## Why a dedicated layer

- The A/B substrate is **SWUpdate + the U-Boot `rootpart` env variable**, not
  Mender's own `fw_setenv`-based `mender-uboot` path. SWUpdate owns the rootfs
  write (raw + zlib to the inactive slot) and sets `rootpart` through its
  bootloader handler. Mender only orchestrates the deployment and the reboot,
  so `mender-full` is off and `meta-mender-client-only` is used.
- The image needs an **explicit wic layout** (boot + two rootfs slots + a
  persistent media partition) rather than meta-mender's auto-partitioning.

## How it works (end to end)

1. The Mender server deploys a `.mender` Artifact of payload type `swu` carrying
   a `.swu`.
2. The Mender client invokes `/usr/share/mender/modules/v3/swu` (this layer's
   module). In `ArtifactInstall` it determines the **inactive** slot from the
   currently-booted rootfs and runs `swupdate -i <staged>.swu -e stable,copyN`.
3. SWUpdate writes the rootfs to the inactive slot (`copy1` → `vda2`,
   `copy2` → `vda3`) and sets U-Boot `rootpart` to `2` or `3` via its
   bootloader handler (`sw-description` `uboot:` section).
4. `NeedsArtifactReboot` returns `Automatic`; Mender reboots.
5. Our `boot.scr` (compiled from `boot.cmd`, placed in the FAT boot partition)
   reads `rootpart` and boots `/dev/vda${rootpart}`, loading `/boot/Image` from
   that slot.

```
| part | mount  | fs   | size | label  |
|------|--------|------|------|--------|
| vda1 | /boot  | vfat | 63M  | boot   |  u-boot.bin, boot.scr.uimg, uboot.env
| vda2 | /      | ext4 | 256M | root-a |  slot A
| vda3 | (B)    | ext4 | 256M | root-b |  slot B (populated by the first OTA)
| vda4 | /media | ext4 | 448M | media  |  persistent
```

## OTA round-trip status

The full server-driven OTA round-trip against hosted.mender.io is **green
end-to-end** (CI "Capability C" step + `hardware-test/tools/qemu_swupdate_ota.py`
in `mender-integration-builds`): the device enrols, is accepted, reports
inventory, the `swu` module installs the payload to the inactive slot and flips
the U-Boot `rootpart`, the device reboots into the new slot, mender **commits**,
and the server reports success.

Two things were load-bearing to get the commit to complete:
- **Persistent Mender state across the A/B swap:** vda4 is mounted *directly* at
  `/var/lib/mender` (see `mender-swupdate-data` + the fstab fragment) so the
  agent key + state DB survive the rootfs swap and the rebooted slot resumes and
  commits the deployment instead of re-enrolling a fresh identity.
- **Stable QEMU identity hygiene in the test driver** (the slirp MAC is fixed):
  the driver selects/accepts only the device matching the QEMU MAC and uses a
  unique artifact name per run.

## Buffered vs streaming

This module does **streaming** (the demo's end state), with a buffered fallback:

- **Streaming (default).** SWUpdate runs as a daemon (`swupdate.service`,
  enabled; plain IPC mode, no webserver/suricatta) listening on its control
  socket `/tmp/sockinstctrl`. In Mender's `Download` state the module reads the
  `stream-next` pipe and hands each payload's named pipe to `swupdate-client
  -e <set,mode> -s /tmp/sockinstctrl <stream>`, which streams it over IPC into
  the daemon — so the `.swu` is never fully staged to disk. The daemon installs
  to the inactive slot as the bytes arrive; `ArtifactInstall` is then a no-op.
  `ProvidePayloadFileSizes` answers `No` (plain `Download`, not
  `DownloadWithFileSizes`).
- **Buffered fallback.** If the streams are not consumed in `Download` (e.g. the
  daemon is not running, or `Download` is disabled), Mender stages the payload to
  `$FILES/files/*.swu` and `ArtifactInstall` runs a one-shot `swupdate -i`. This
  mirrors the upstream `mendersoftware/mender-update-modules` `swu` module.

Note on the Mender contract ("an update module must not install to the final
location during `Download`", since artifact checksums verify as the stream
completes): for an A/B update this is acceptable — SWUpdate writes only the
**inactive** slot during `Download`; that slot is activated (`rootpart`) and
booted only after Mender's verification + the reboot/commit, so a truncated or
checksum-failed stream (which also fails `swupdate-client`, aborting the
deployment) never reaches a booted system.

## Runtime notes / quirks

- **Persistent U-Boot env in FAT.** qemu virt has no MMC/flash, so the env is
  stored as `uboot.env` in the FAT boot partition
  (`recipes-bsp/u-boot/files/swupdate-uboot.cfg`, a config fragment rather than
  a version-pinned source patch). The Linux side reaches the same file through
  `/etc/fw_env.config`. The env size (`0x4000`) must match on both sides.
- **boot.scr, not a U-Boot source patch.** The slot-selection logic lives in
  `boot.cmd` → `boot.scr.uimg` and is found by U-Boot's distroboot scan. This
  avoids patching `config_distro_bootcmd.h` for each U-Boot release.
- **Hardware version.** Fixed at `1.0` for the demo; it appears in the module's
  `swupdate -H 1.0:1.0`, the kas `SWUPDATE_HARDWARE_VERSION`, and the
  `sw-description` board section + `hardware-compatibility` list. Keep them in
  sync.
- **No rollback yet.** Like the upstream `swu` module, `SupportsRollback` is
  `No`. Bootloader-level auto-rollback (U-Boot `bootcount`/`altbootcmd` +
  SWUpdate `ustate`, with `ArtifactCommit` marking the slot good) is a natural
  enhancement.

## Dependencies

Requires `meta-swupdate` (branch `wrynose`), `meta-openembedded`
(`meta-python`, `meta-networking`, `meta-filesystems`), and
`meta-mender-community`'s `meta-mender-client-only`. Use the
`qemuarm64-swupdate.yml` kas config in `mender-community-images`:

```
kas shell qemuarm64-swupdate.yml
bitbake all-images
runqemu nographic slirp
```

`bitbake all-images` produces both the flashable `main-image-*.wic` and the
`swu-image-*.swu` OTA payload; wrap the latter into a `.mender` Artifact with
`mender-artifact write module-image -T swu`.
