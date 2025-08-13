# meta-mender-toradex-nxp

Mender integration for Toradex NXP boards

The supported and tested boards are:

- [Toradex Apalis iMX6](https://hub.mender.io/c/board-integrations/)
- [Toradex Apalis iMX8](https://hub.mender.io/c/board-integrations/)
- [Toradex Colibri iMX6ULL](https://hub.mender.io/c/board-integrations/)
- [Toradex Colibri iMX8X](https://hub.mender.io/c/board-integrations/)
- [Toradex Verdin iMX8M Mini](https://hub.mender.io/c/board-integrations/)
- [Toradex Verdin iMX8M Plus](https://hub.mender.io/c/board-integrations/)

Visit the individual board links above for more information on status of the
integration and more detailed instructions on how to build and use images
together with Mender for the mentioned boards.

## Dependencies

This layer depends on:

```
URI: https://git.yoctoproject.org/git/poky
branch: scarthgap
revision: HEAD
```

```
URI: https://github.com/mendersoftware/meta-mender.git
layers: meta-mender-core
branch: scarthgap
revision: HEAD
```

```
URI: https://git.toradex.com/meta-toradex-nxp.git
branch: scarthgap-7.x.y
revision: HEAD
```

```
URI: https://git.toradex.com/meta-toradex-bsp-common.git
branch: scarthgap-7.x.y
revision: HEAD
```

```
URI: https://git.toradex.com/meta-toradex-distro.git
branch: scarthgap-7.x.y
revision: HEAD
```

```
URI: https://github.com/Freescale/meta-freescale.git
branch: scarthgap
revision: HEAD
```

```
URI: https://git.openembedded.org/meta-openembedded
branch: scarthgap
revision: HEAD
```

## Quick start

See the top level [README](../README.md) for instructions to build using the `kas` tool. Supported configurations are:

- [`apalis-imx6.yml`](../kas/apalis-imx6.yml)
- [`apalis-imx8.yml`](../kas/apalis-imx8.yml)
- [`colibri-imx6ull.yml`](../kas/colibri-imx6ull.yml)
- [`colibri-imx8x.yml`](../kas/colibri-imx8x.yml)
- [`verdin-imx8mm.yml`](../kas/verdin-imx8mm.yml)
- [`verdin-imx8mp.yml`](../kas/verdin-imx8mp.yml)