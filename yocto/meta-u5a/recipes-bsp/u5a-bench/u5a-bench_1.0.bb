SUMMARY = "V851S box integration: init, settings page, OTA, radio configs, out-of-tree modules and BT firmware"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

# The kernel and its modules are built outside Yocto (scripts/build-kernel.sh, scripts/build-modules.sh).
# U5A_REPO (set in local.conf) is this repository: modules from build/modules, the Realtek Bluetooth
# firmware from blobs/ (not redistributable here, see blobs/README.md).
U5A_REPO ??= ""
U5A_KREL = "7.2.7-v851s-p5"
FILESEXTRAPATHS:prepend := "${THISDIR}/files:${U5A_REPO}/build/modules:${U5A_REPO}/blobs:"
python () {
    if not d.getVar('U5A_REPO'):
        bb.fatal("set U5A_REPO in local.conf to the catplay-v851s checkout")
}

SRC_URI = " \
    file://u5a-init file://u5a-settings file://u5a-catplay-run file://u5a-snapshot file://settings-defaults.conf \
    file://www/index.html file://www/cgi-bin/status file://www/cgi-bin/save file://www/cgi-bin/apply file://www/cgi-bin/update \
    file://catplay-bench.conf file://catplay-car.conf file://hostapd.conf file://udhcpd-wifi.conf \
    file://udhcpd-usb.conf file://bluetooth-main.conf \
    file://rtl8723fs_fw.bin file://rtl8723fs_config.bin \
    file://crc-ccitt.ko file://btrtl.ko file://hci_uart.ko file://8733bs.ko \
    file://iap2_char.ko file://iap2_scan.ko file://g_iphone.ko \
"
S = "${UNPACKDIR}"

do_install() {
    install -Dm 0755 ${S}/u5a-init ${D}${base_sbindir}/u5a-init
    install -Dm 0755 ${S}/u5a-settings ${D}${sbindir}/u5a-settings
    install -Dm 0755 ${S}/u5a-catplay-run ${D}${sbindir}/u5a-catplay-run
    install -Dm 0755 ${S}/u5a-snapshot ${D}${sbindir}/u5a-snapshot
    install -Dm 0644 ${S}/settings-defaults.conf ${D}${sysconfdir}/u5a/settings-defaults.conf
    install -Dm 0644 ${S}/www/index.html ${D}/www/index.html
    for c in status save apply update; do install -Dm 0755 ${S}/www/cgi-bin/$c ${D}/www/cgi-bin/$c; done
    for f in catplay-bench.conf catplay-car.conf hostapd.conf udhcpd-wifi.conf udhcpd-usb.conf bluetooth-main.conf; do
        install -Dm 0644 ${S}/$f ${D}${sysconfdir}/u5a/$f
    done
    install -Dm 0644 ${S}/rtl8723fs_fw.bin ${D}${nonarch_base_libdir}/firmware/rtl_bt/rtl8723fs_fw.bin
    install -Dm 0644 ${S}/rtl8723fs_config.bin ${D}${nonarch_base_libdir}/firmware/rtl_bt/rtl8723fs_config.bin
    for m in crc-ccitt btrtl hci_uart 8733bs iap2_char iap2_scan g_iphone; do
        install -Dm 0644 ${S}/$m.ko ${D}${nonarch_base_libdir}/modules/${U5A_KREL}/extra/$m.ko
    done
    install -d ${D}/persist
}

FILES:${PN} = "${base_sbindir} ${sbindir}/u5a-settings ${sbindir}/u5a-catplay-run ${sbindir}/u5a-snapshot /www ${sysconfdir}/u5a ${nonarch_base_libdir}/firmware ${nonarch_base_libdir}/modules /persist"
# Prebuilt kernel modules and firmware: no target-arch QA on these blobs.
INSANE_SKIP:${PN} += "arch already-stripped"
RDEPENDS:${PN} = "busybox dbus bluez5 hostapd dropbear catplay"
PACKAGE_ARCH = "${MACHINE_ARCH}"

