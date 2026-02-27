SUMMARY = "Mender OTA Demo Application for reTerminal"
DESCRIPTION = "Fullscreen kiosk application that displays Mender device state, \
artifact information, and network status. Two visual themes allow demonstrating \
OTA updates with an immediately visible change."
HOMEPAGE = "https://github.com/mendersoftware/meta-mender-community"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

DEMO_APP_THEME ?= "v1"
DEMO_APP_VERSION ?= "1.0"

SRC_URI = " \
    file://mender-demo-app.py \
    file://theme-v1.css \
    file://theme-v2.css \
    file://mender-logo.svg \
    file://mender-demo-app.service \
    file://mender-demo-app-launch.sh \
"

S = "${WORKDIR}"

RDEPENDS:${PN} = " \
    python3-pygobject \
    python3-pydbus \
    gtk+3 \
    python3-core \
    python3-json \
    librsvg-gtk \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "mender-demo-app.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}/opt/mender-demo-app
    install -m 0755 ${WORKDIR}/mender-demo-app.py ${D}/opt/mender-demo-app/
    install -m 0644 ${WORKDIR}/theme-v1.css ${D}/opt/mender-demo-app/
    install -m 0644 ${WORKDIR}/theme-v2.css ${D}/opt/mender-demo-app/
    install -m 0644 ${WORKDIR}/mender-logo.svg ${D}/opt/mender-demo-app/

    # Symlink selected theme
    ln -sf theme-${DEMO_APP_THEME}.css ${D}/opt/mender-demo-app/theme.css

    # Bake version into the app
    sed -i 's/@DEMO_VERSION@/${DEMO_APP_VERSION}/g' \
        ${D}/opt/mender-demo-app/mender-demo-app.py

    # Launch wrapper
    install -m 0755 ${WORKDIR}/mender-demo-app-launch.sh ${D}/opt/mender-demo-app/

    # Systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/mender-demo-app.service \
        ${D}${systemd_system_unitdir}/
}

FILES:${PN} = " \
    /opt/mender-demo-app \
    ${systemd_system_unitdir}/mender-demo-app.service \
"
