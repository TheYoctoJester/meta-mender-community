# meta-mender-demos-common

Shared building blocks for the wrynose Mender demo layers, factored out so the
individual demos do not each carry a copy.

## Contents

### `mender-data-persist`

Persists Mender runtime state (`/var/lib/mender`: the agent key and the LMDB
state DB) on the `/data` partition so it survives an A/B rootfs swap.

It ships:

- a systemd-tmpfiles snippet (`mender-data-persist.conf`) that seeds
  `/data/mender` from the build-time `/var/lib/mender` on first boot only; and
- `var-lib-mender.mount`, which bind-mounts `/data/mender` over
  `/var/lib/mender` before `mender-authd`/`mender-updated` start.

Add it to a demo image with `IMAGE_INSTALL:append = " mender-data-persist"`.

This is needed by demos that disable the `mender-image` feature (so Mender's own
relocation of state onto the data partition is off) while the bootloader/firmware
owns A/B — e.g. the efibootmgr and x86 U-Boot EFI demos, which previously each
shipped a byte-identical `mender-*-data` recipe.

Note: demos where an external updater owns the rootfs and uses a different
ordering (e.g. RAUC's seed *service*), or where state is persisted by mounting
the data partition directly at `/var/lib/mender` (e.g. SWUpdate), do not use this
recipe.

Maintainer: Josef Holzmayr <jester@theyoctojester.info>
