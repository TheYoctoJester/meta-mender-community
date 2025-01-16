def mender_sdimg_get_full_gb(d):
    return int((int(d.getVar('MENDER_STORAGE_TOTAL_SIZE_MB')) + 1023) / 1024)

IMAGE_CMD:sdimg:append() {
    outimgname="${IMGDEPLOYDIR}/${IMAGE_NAME}.$suffix"
    qemu-img resize -f raw ${outimgname} ${@mender_sdimg_get_full_gb(d)}G
}

do_image_sdimg[depends] += "qemu-system-native:do_populate_sysroot"