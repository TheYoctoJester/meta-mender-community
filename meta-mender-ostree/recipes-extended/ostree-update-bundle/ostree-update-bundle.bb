SUMMARY = "Build-time OSTree v2 commit + static delta (the OSTree demo OTA payload)"
DESCRIPTION = "Produces the update the OSTree demo deploys over the air: checks \
out the image's OSTree commit (v1), applies a trivial change, commits it as v2 \
on the same branch, and generates a self-contained static delta v1->v2 \
(--min-fallback-size=0). The delta + the v2 commit checksum are deployed for CI \
to wrap into a Mender artifact of payload type 'ostree', which the ostree \
Update Module applies with 'static-delta apply-offline' + 'ostree admin deploy'."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

DEPENDS = "ostree-native"
INHIBIT_DEFAULT_DEPS = "1"
EXCLUDE_FROM_WORLD = "1"

# OSTree repo + branch are set globally by the kas wrapper (same values the
# image build uses).
OSTREE_REPO ?= "${DEPLOY_DIR_IMAGE}/ostree_repo"
OSTREE_BRANCHNAME ??= "${MACHINE}"
OSTREE_DELTA_FILE ?= "ostree-delta-v2"

inherit deploy

# Needs the image's OSTree commit (v1) in the repo.
do_deploy[depends] += "mender-ostree-image:do_image_complete"

do_deploy() {
    # Work on a copy so we never mutate the image's deploy repo.
    rm -rf ${WORKDIR}/repo ${WORKDIR}/co
    cp -a ${OSTREE_REPO} ${WORKDIR}/repo

    v1=$(ostree --repo=${WORKDIR}/repo rev-parse ${OSTREE_BRANCHNAME})
    ostree --repo=${WORKDIR}/repo checkout -U ${OSTREE_BRANCHNAME} ${WORKDIR}/co

    # The demonstrable change carried by the OTA (a genuinely different commit;
    # deploying the same commit would be a no-op).
    install -d ${WORKDIR}/co/usr/lib/mender-ostree-demo
    echo "2" > ${WORKDIR}/co/usr/lib/mender-ostree-demo/version

    v2=$(ostree --repo=${WORKDIR}/repo commit -b ${OSTREE_BRANCHNAME} \
             -s "OSTree demo v2" --tree=dir=${WORKDIR}/co)

    ostree --repo=${WORKDIR}/repo static-delta generate \
        --from=${v1} --to=${v2} --min-fallback-size=0 \
        --filename=${WORKDIR}/${OSTREE_DELTA_FILE}

    echo "${v2}" > ${WORKDIR}/${OSTREE_DELTA_FILE}.commit
    bbnote "OSTree demo static delta ${v1} -> ${v2}"

    install -d ${DEPLOYDIR}
    install -m 0644 ${WORKDIR}/${OSTREE_DELTA_FILE} ${DEPLOYDIR}/${OSTREE_DELTA_FILE}
    install -m 0644 ${WORKDIR}/${OSTREE_DELTA_FILE}.commit ${DEPLOYDIR}/${OSTREE_DELTA_FILE}.commit
}
addtask deploy before do_build after do_compile
