# meta-mender-rauc

Manage a [RAUC](https://rauc.io)-updated A/B system from the Mender server on
Yocto wrynose. RAUC stays the on-device updater; the Mender server delivers the
RAUC bundle inside a Mender artifact and a custom Update Module installs it.
End-to-end verified against hosted.mender.io on `qemuarm64`.

## Division of responsibility

* **RAUC** owns the A/B layout, the signed bundle format, the slot switch and
  the bootloader attempt-counter rollback. The A/B machine itself — slots,
  `update-bundle` recipe and the u-boot bootscript — comes from
  `rauc/meta-rauc-community`'s `meta-rauc-qemuarm`, not from this layer.
* **Mender** owns fleet connectivity, inventory, deployment orchestration, the
  reboot and the commit signal.
* **This layer** is the glue between the two. It carries no machine or slot
  definitions; it assumes the `meta-rauc-qemuarm` layout (rootfs slots
  `/dev/vda2`/`/dev/vda3`, data partition `/dev/vda4` at `/data`, compatible
  string `qemuarm demo`).

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

* `recipes-mender/mender-rauc-data/` — a tmpfiles snippet that seeds
  `/data/mender` from the build-time `/var/lib/mender` on first boot, plus a
  `var-lib-mender.mount` unit that bind-mounts `/data/mender` over
  `/var/lib/mender` before the mender services start. This keeps the Mender
  state DB and the agent key on RAUC's persistent `/data` partition so they
  survive the rootfs swap of an A/B OTA.

* `recipes-mender/update-bundle-mender/` — wraps the `.raucb` produced by
  `meta-rauc-qemuarm`'s `update-bundle` into a Mender artifact of payload type
  `rauc` (`mender-artifact write module-image -T rauc`). Bump
  `MENDER_RAUC_ARTIFACT_NAME` per release so deployments are meaningful.

## Two runtime quirks worth knowing

Each cost a build/deploy cycle to discover; they're why the layer is shaped
this way:

1. **Mender state must live on `/data`.** The Mender client keeps its identity
   key + state DB in `/var/lib/mender`, which a RAUC A/B update replaces along
   with the rootfs. Without the bind mount above, the device re-enrols after
   every update and the post-reboot commit reports `Failure` even though the
   RAUC slot switch was correct. The tmpfiles `C` seed + the `.mount` unit fix
   this (cf. the same pattern in `meta-mender-uki`).

2. **`/etc/fw_env.config` can go missing.** meta-mender's `libubootenv`
   bbappend adds `RPROVIDES u-boot-default-env`, so with
   `PREFERRED_RPROVIDER_u-boot-default-env = "libubootenv"` the `u-boot-env`
   package that ships `/etc/fw_env.config` is no longer pulled in, and RAUC can
   no longer read/write the u-boot environment (both slots show as `bad`). The
   kas wrapper re-adds `u-boot-env` to `IMAGE_INSTALL` to restore it.

## Reproducing the build

This layer is consumed by the matching kas wrapper at
`yocto/wrynose/floating/qemuarm64-rauc.yml` on branch `wrynose-demos` of
`theyoctojester/mender-community-images`:

```sh
git clone https://github.com/theyoctojester/mender-community-images.git
cd mender-community-images
git checkout wrynose-demos
kas build yocto/wrynose/floating/qemuarm64-rauc.yml
```

The wrapper composes `meta-rauc` (wrynose) + `rauc/meta-rauc-community`'s
`meta-rauc-qemuarm` (compat-forced to wrynose) + `meta-mender-client-only` +
this layer, and inherits the rest of the wrynose stack (oe-core, meta-yocto,
meta-openembedded, meta-mender) from the existing `include/mender-base.yml`.
Server URL and tenant token are provided by the builder (e.g. in a local
override), not committed.

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
`rauc-qemuarm64-<n>.mender` artifact, deploy it, and observe install -> reboot
(slot A -> B) -> `rauc status mark-good` -> deployment `Success`, with the
device reporting the new artifact name.

## License

`meta-mender-rauc/LICENSE` (Apache-2.0). Individual recipes specify their own
`LICENSE` per Yocto convention.
