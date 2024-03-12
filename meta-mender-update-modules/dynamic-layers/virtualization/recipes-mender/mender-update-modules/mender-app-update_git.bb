DESCRIPTION = "Mender Application Update Module for supporting containerized application updates on devices including related tools ."

HOMEPAGE = "https://mender.io"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=30b4554c64108561c0cb1c57e8a044f0"

SRC_URI = "git://github.com/mendersoftware/app-update-module;branch=master;protocol=https"

SRCREV = "dffbcb927275397f436a0f0b6d95b75d035dd37e"

S = "${WORKDIR}/git"

RDEPENDS:${PN} = "jq mender-client xdelta3"

inherit allarch

do_configure[noexec] = "1"
do_compile[noexec] = "1"

do_install:class-target() {
	# install Application Update Module
    install -d ${D}/${datadir}/mender/modules/v3
    install -m 755 ${S}/src/app ${D}/${datadir}/mender/modules/v3/app

	# install K8s/K3s Module
    install -d ${D}/${datadir}/mender/app-modules/v1
    install -m 755 ${S}/src/app-modules/k8s ${D}/${datadir}/mender/app-modules/v1/k8s

	# install configuration files
    install -d ${D}/${sysconfdir}/mender
    install -m 755 ${S}/conf/mender-app.conf ${D}/${sysconfdir}/mender/mender-app.conf
    install -m 755 ${S}/conf/mender-app-docker-compose.conf ${D}/${sysconfdir}/mender/mender-app-k8s.conf
}

do_install:class-native() {
    install -d ${D}/${bindir}
    install -m 755 ${S}/gen/app-gen ${D}/${bindir}/app-gen
}

FILES:${PN} += "${datadir}/mender/modules/v3/app"
FILES:${PN} += "${datadir}/mender/app-modules/v1/k8s"

FILES:${PN}-class-native += "${bindir}/app-gen"

BBCLASSEXTEND = "native"
