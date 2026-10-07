SUMMARY = "CatPlay image for V851S boxes (EROFS root mounted in place: root=/dev/initrd rootfstype=erofs init=/sbin/u5a-init)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit c2a-x-ro

IMAGE_FSTYPES = "erofs-lz4hc"
# 64 MiB board: keep catplay_c2a paged from the compressed EROFS image instead of UPX-unpacked into RAM (as V821).
IMAGE_UPX_TARGETS:forcevariable = ""
# Kernel and modules are built outside Yocto (u5a-bench ships the modules).
PACKAGE_INSTALL:remove = "kernel-modules"
PACKAGE_INSTALL:append = " u5a-bench"

# Firmware version shown on the settings page: written when the image is assembled, so it changes with
# every image (a package-level date would stay stale when only catplay changes).
u5a_write_version() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/u5a
    echo "catplay-v851s ${DATETIME}" > ${IMAGE_ROOTFS}${sysconfdir}/u5a/version
}
ROOTFS_POSTPROCESS_COMMAND += "u5a_write_version"
u5a_write_version[vardepsexclude] += "DATETIME"
