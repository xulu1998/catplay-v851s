# g_iphone.ko is built against our out-of-tree kernel (scripts/build-modules.sh), not by Yocto.
RDEPENDS:${PN}:remove:u5a = "catplay-g-iphone"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
# 0002 + 0003 (submitted upstream, catplay-labs/catplay#34): head units like the 2024 Kia Sportage (Hyundai Mobis D-Audio) only
#   invite the device after DeviceTransportIdentifierNotification / DeviceLanguageUpdate, which they list
#   in IdentificationInformation; 0002 fixes the ID list decoding that 0003 relies on.
# 0004 + u5a-logo.jpg: your own picture on the connection screen (replace the JPEG, 512x512).
# 0005: info-level log of head-unit touch (HID) events, for diagnosis.
# 0006 (submitted upstream, catplay-labs/catplay#35, fixes #18): keep paging the last iPhone after the first minute, so a phone
#   that reaches the car late still reconnects without touching it.
# 0007 (proposed upstream): after the car session ends (e.g. the phone's Wi-Fi goes off), invite the
#   legacy head unit again instead of leaving it frozen until replug.
# 0008 (submitted upstream with 0006, catplay-labs/catplay#35): when a session ends, page the phone again so CarPlay comes back by
#   itself when the phone does.
# 0009 (interim): CSeq sanity check off; recent iOS versions trip it and the session drops. Upstream drops
#   the check in its next release (maintainer, catplay-labs/catplay#35); remove 0009 when updating catplay.
# 0001 (debug-level logs in release builds) is kept for diagnosis builds and not applied.
SRC_URI:append:u5a = " file://0002-catplay_csm-fix-IdentificationInformation-unpack_ids-and-has_id.patch \
                       file://0003-catplay_carplay_tx_gadget-send-transport-IDs-and-language.patch \
                       file://0004-ui-u5a-logo-cache-version.patch file://u5a-logo.jpg \
                       file://0005-u5a-log-hid-events.patch \
                       file://0006-catplay_carplay_rx_gadget-keep-paging-the-last-iPhone.patch \
                       file://0007-catplay_carplay_tx_gadget-re-arm-the-legacy-self-invite.patch \
                       file://0008-catplay_carplay_rx_gadget-page-the-iPhone-again-when-a-session-ends.patch \
                       file://0009-catplay_carplay-do-not-enforce-CSeq-sanity.patch"

do_compile:prepend:u5a() {
    install -m 0644 ${UNPACKDIR}/u5a-logo.jpg ${S}/c2a/catplay_c2a/assets/logo.jpg
}
