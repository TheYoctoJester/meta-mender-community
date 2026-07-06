# meta-mender-rauc

**Status: verified end-to-end** (qemu OTA run #2450; RPi4 hardware OTA on dut1 run #2443).

Manage a [RAUC](https://rauc.io)-updated A/B system from the Mender server on
Yocto wrynose. RAUC stays the on-device updater; the Mender server delivers the
RAUC bundle inside a Mender artifact and a custom Update Module installs it.
End-to-end verified against hosted.mender.io on `qemuarm64` (QEMU) and on
`raspberrypi4-64` (real hardware).

## Division of responsibility

* **RAUC** owns the A/B layout, the signed bundle format, the slot switch and
  the bootloader attempt-counter rollback. The A/B machine itself — slots,
  `update-bundle` recipe and the u-boot bootscript — comes from a
  `rauc/meta-rauc-community` board layer, **not** from this layer:
  `meta-rauc-qemuarm` for `qemuarm64`, `meta-rauc-raspberrypi` for the Pi.
* **Mender** owns fleet connectivity, inventory, deployment orchestration, the
  reboot and the commit signal.
* **This layer** is the glue between the two. It is board-agnostic: it carries
  no machine or slot definitions and only ever talks to `rauc`. It assumes the
  chosen board layer provides RAUC's slots, a persistent `/data` partition and
  a u-boot environment RAUC can read. Per-board specifics (e.g. qemuarm:
  `/dev/vda2`/`vda3` + `/dev/vda4` at `/data`, compatible `qemuarm demo`;
  raspberrypi4-64: `/dev/mmcblk0p2`/`p3` + `/dev/mmcblk0p5` at `/data`,
  compatible `raspberrypi4-64`) come entirely from that layer.

## Why a dedicated layer

RAUC and the Mender rootfs A/B integration are two different update mechanisms
and must not both own the rootfs. The supported way to drive a non-Mender
updater from the Mender server is the Mender client in *client-only* mode plus
an Update Module (cf. `meta-mender-client-only` and `meta-mender-update-modules`).
This layer adds the RAUC-specific module and the small amount of glue that the
client-only setup leaves to the integrator.

## What this layer provides

* `recipes-mender/rauc-update-module/` — the `rauc` v3 Update Module installed
  at `/usr/share/mender/modules/v3/rauc`. It maps the Mender update lifecycle
  onto RAUC: `ArtifactInstall` runs `rauc install <bundle.raucb>`,
  `NeedsArtifactReboot` is `Automatic`, `ArtifactVerifyReboot` asserts the boot
  switched to the other slot, `ArtifactCommit` runs `rauc status mark-good`, and
  `ArtifactRollback` re-activates the previously booted slot. The payload is a
  single signed `.raucb` in the artifact; RAUC verifies it against its keyring.

* `recipes-mender/mender-rauc-data/` — a `mender-rauc-data-seed.service` that
  seeds `/data/mender` from the build-time `/var/lib/mender` on first boot, plus
  a `var-lib-mender.mount` unit that bind-mounts `/data/mender` over
  `/var/lib/mender` before the mender services start. This keeps the Mender
  state DB and the agent key on RAUC's persistent `/data` partition so they
  survive the rootfs swap of an A/B OTA. The seed is a service rather than a
  tmpfiles `C` rule so it can be ordered explicitly *before*
  `mender-data-dir.service` (meta-mender's own `mkdir /data/mender`) and the
  bind mount; otherwise an empty `/data/mender` could win that race and the
  bind mount would shadow the rootfs `device_type`, leaving the device unable
  to report `device_type` inventory.

* `recipes-mender/update-bundle-mender/` — wraps the `.raucb` produced by
  `meta-rauc-qemuarm`'s `update-bundle` into a Mender artifact of payload type
  `rauc` (`mender-artifact write module-image -T rauc`). Bump
  `MENDER_RAUC_ARTIFACT_NAME` per release so deployments are meaningful.

* `recipes-mender/rauc-inventory/` — a `mender-inventory-rauc` script installed
  at `/usr/share/mender/inventory/mender-inventory-rauc`. The Mender client runs
  it periodically and reports its `key=value` output as device inventory. It
  parses `rauc status --detailed --output-format=json` (via `jq`) and emits two
  kinds of attributes.

  First, the **booted** slot's installed RAUC bundle under Mender's canonical
  software-versioning keys — `rootfs-image.version` (the RAUC bundle version)
  and `rootfs-image.checksum` (its sha256) — exactly the keys a native Mender
  rootfs device reports from the rootfs-image artifact's *provides*. The Mender
  server renders `<name>.version`/`.checksum` inventory as installed software, so
  this makes the running RAUC bundle appear in the device **Software** tab like a
  stock rootfs device. (These appear once a bundle has been installed on the
  running slot; a freshly-flashed slot has no RAUC install record.)

  Second, descriptive RAUC status as generic `rauc_*` inventory — the system
  compatible/booted/primary and, per slot, bootname/state/boot-status and the
  installed bundle version/compatible/timestamp, e.g.:

  ```
  rootfs-image.version=1.0
  rootfs-image.checksum=ef05455927267df10ca684e525b2aaad845f726bf84a95d614c522da4c091485
  rauc_compatible=qemuarm demo
  rauc_booted=B
  rauc_boot_primary=rootfs.1
  rauc_slot_rootfs_1_state=booted
  rauc_slot_rootfs_1_boot_status=good
  rauc_slot_rootfs_1_bundle_version=1.0
  rauc_slot_rootfs_0_state=inactive
  ```

  This complements the `rootfs-image.rauc.version` reported via the artifact's
  *provides* (which names the deployed Mender artifact): `rootfs-image.version`
  here is the RAUC-level bundle version read live from the booted slot.

* `recipes-mender/mender/mender_%.bbappend` — removes the Mender client's stock
  `rootfs-image` Update Module from the image. RAUC owns the rootfs A/B, so
  `rootfs-image` (which does its own writing to `MENDER_ROOTFS_PART_A/B`) is
  conflicting; the `single-file`, `directory` and `rauc` modules remain.

## Two runtime quirks worth knowing

Each cost a build/deploy cycle to discover; they're why the layer is shaped
this way:

1. **Mender state must live on `/data`.** The Mender client keeps its identity
   key + state DB in `/var/lib/mender`, which a RAUC A/B update replaces along
   with the rootfs. Without the bind mount above, the device re-enrols after
   every update and the post-reboot commit reports `Failure` even though the
   RAUC slot switch was correct. The seed service + the `.mount` unit fix
   this (cf. the same pattern in `meta-mender-uki`).

2. **`/etc/fw_env.config` can go missing.** meta-mender's `libubootenv`
   bbappend adds `RPROVIDES u-boot-default-env`, so with
   `PREFERRED_RPROVIDER_u-boot-default-env = "libubootenv"` the `u-boot-env`
   package that ships `/etc/fw_env.config` is no longer pulled in, and RAUC can
   no longer read/write the u-boot environment (both slots show as `bad`). The
   kas wrapper re-adds `u-boot-env` to `IMAGE_INSTALL` to restore it.

## Reproducing the build

This layer is consumed by matching kas wrappers on branch `wrynose-demos` of
`theyoctojester/mender-community-images`, one per board:

```sh
git clone https://github.com/theyoctojester/mender-community-images.git
cd mender-community-images
git checkout wrynose-demos
kas build yocto/wrynose/floating/qemuarm64-rauc.yml        # QEMU
kas build yocto/wrynose/floating/raspberrypi4-64-rauc.yml  # Raspberry Pi 4
```

Each wrapper composes `meta-rauc` (wrynose) + a `rauc/meta-rauc-community` board
layer + `meta-mender-client-only` + this layer, and inherits the rest of the
wrynose stack (oe-core, meta-yocto, meta-openembedded, meta-mender) from the
existing `include/mender-base.yml`. Server URL and tenant token are provided by
the builder (e.g. in a local override), not committed.

* **qemuarm64**: `meta-rauc-qemuarm`, compat-forced to wrynose in
  `bblayers_conf_header` (the layer declares only `styhead..whinlatter`).
* **raspberrypi4-64**: `meta-rauc-raspberrypi` + `meta-raspberrypi`. The layer
  already declares wrynose compat (no force needed) and brings the U-Boot
  bootscript, the dual-rootfs wks (`mmcblk0p2`/`p3` slots, `/data`, `/home`)
  and `RDEPENDS u-boot-fw-utils u-boot-env` so `/etc/fw_env.config` is present.
  The wrapper sets short Mender poll intervals so a server deployment is picked
  up quickly. One caveat: `meta-rauc-raspberrypi`'s `update-bundle` hardcodes
  `RAUC_BUNDLE_VERSION`; override it per release if you want the RAUC-level
  bundle version (reported via `rauc-inventory` as `rootfs-image.version`) to
  be meaningful — the Mender artifact name (`rauc-raspberrypi4-64-<n>`) already
  bumps independently.

## Verification recipe

After `kas build`, boot the wic in QEMU:

```sh
kas shell yocto/wrynose/floating/qemuarm64-rauc.yml \
    -c "runqemu core-image-minimal wic.qcow2 nographic slirp"
```

Inside the guest the following should hold:

```sh
rauc status                                   # slots A/B "good", env readable
mountpoint /var/lib/mender                    # bind mount from /data
ls /usr/share/mender/modules/v3/rauc          # the update module is present
systemctl is-active mender-updated mender-authd
```

End-to-end against the Mender server: enrol and accept the device, upload the
`rauc-<machine>-<n>.mender` artifact, deploy it, and observe install -> reboot
(slot A -> B) -> `rauc status mark-good` -> deployment `Success`, with the
device reporting the new artifact name. On real hardware this is automated in
`theyoctojester/mender-integration-builds` (`build-yocto-wrynose-demo.yml`),
which builds `raspberrypi4-64-rauc` and runs the full OTA on an RPi4 DUT
(`hardware-test/tests/test_flash_and_ota.py`) against hosted.mender.io, logging
into the management API with credentials set in the workflow job env.

## License

`meta-mender-rauc/LICENSE` (Apache-2.0). Individual recipes specify their own
`LICENSE` per Yocto convention.
