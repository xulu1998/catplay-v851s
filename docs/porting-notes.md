# Porting notes: CatPlay on V851S + RTL8733BS

How the pieces CatPlay expects were provided on this board, and what was learned on the way. The full
chronological log is in [experiment-log.md](experiment-log.md).

## What CatPlay needs

[CatPlay](https://github.com/catplay-labs/catplay) (`catplay_c2a`) is both sides of the adapter: a
wireless CarPlay receiver toward the iPhone (Bluetooth + Wi-Fi) and a wired "iPhone" toward the car
(USB, through the `g_iphone` gadget module). Upstream's firmware
([catplay-firmware](https://github.com/catplay-labs/catplay-firmware)) is a Yocto BSP; its init
(`carlinkit_otalib`) knows only the Ingenic, i.MX and V821 boards.

| Needs | Provided by |
| --- | --- |
| Mainline kernel with BT H5/RTL, I2C, USB role switch, IPv6, EROFS | Linux 7.2.7 + kernel/patches-linux-7.2.7: 0001–0013 from catplay-firmware's meta-sunxi (btrtl RTL8733BS, musb/phy role switch for the V821 port, cdc-ncm, EROFS root in place); 0014 V851S/V853 SoC support from prototype-v851s-port; 0015 macOS host build |
| Wi-Fi AP (5 GHz) | rtl8733bs v5.14.1.1 driver ported to 7.2 (kernel/patches-rtl8733bs), hostapd, `rtw_country_code` set |
| Bluetooth | hci_uart serdev H5 + btrtl, RTL8723FS firmware from the factory customer partition |
| MFi | TWI3, `bus_offset = 3`, `dev_addr = 0x11` |
| Car-side USB | g_iphone with a `role_switch_name` parameter (kernel/patches-g_iphone): on V851S the UDC is `musb-hdrc.2.auto` but the role switch is `4100000.usb` |
| Init | `u5a-init` (shell): mounts /persist, starts dbus, bluetoothd, hostapd, udhcpd, the settings page and catplay |
| Userspace | Yocto layer yocto/meta-u5a: machine `v851s-rtl8733bs` (cortexa7thf-neon-vfpv4, c2a-musl, clang), image `u5a-e28-image` (EROFS lz4hc, about 9.4 MiB) |

RAM is the tight resource: about 30 MB is available with everything running. The root stays
compressed (EROFS mounted in place), the catplay log is filtered and capped (`u5a-catplay-run`).

## CatPlay patches (yocto/meta-u5a/recipes-apps/catplay/files)

- **0002 + 0003 (needed for Hyundai/Kia head units, submitted as catplay-labs/catplay#34).** The 2024 Kia Sportage head
  unit (Hyundai Mobis "D-Audio", telechips `wp_daudioplus`, iAP2 identity "Sportage" / "NQ5") lists
  DeviceTransportIdentifierNotification (0x4E0E) and DeviceLanguageUpdate (0x4E0A) among the messages
  it accepts, and never invites the device over CarPlay-control until it has received them: the car
  showed "Reading USB" for two seconds and nothing else. 0003 sends both after authentication when the
  head unit lists them. 0002 fixes `IdentificationInformation::unpack_ids` (always returned an empty
  list) and `has_id` (looped forever), which 0003 relies on. Drafts of the upstream report are in
  [upstream/](upstream/).
- **0006 + 0008 (reconnecting the phone, submitted as catplay-labs/catplay#35, fixes #18).** The phone is paged over
  Bluetooth only for the first minute after start, and not at all after a session: the iPhone drops its
  Bluetooth link once the wireless session is up, so after its Wi-Fi went off and on, or when it reached
  the car late, CarPlay only came back after connecting Bluetooth by hand. 0006 keeps paging every 10 s
  after the first minute; 0008 starts paging again when a session ends. Tested in the car: after the
  phone's Wi-Fi goes off and on, it reconnects by itself. The late-arrival case is verified on the box
  (paging continues) but not yet in the car.
- **0007 (proposed upstream).** Head units without the CARPLAY_CONTROL flag (the Kia) never invite on their
  own; CatPlay invites itself once per USB session. Once, turning the phone's Wi-Fi off made CatPlay end
  the car session ("iPhone disconnected while command proxies were inflight"); the car was never invited
  again, the screen froze and the car stopped using the adapter until replug. 0007 allows the self-invite
  again after a car session of at least 10 s ends. The case has not happened again since, so 0007 itself
  is not yet confirmed in the car.
- 0004: bumps the UI cache version so a changed connection-screen logo is re-rendered.
- 0005: diagnostics only: logs head-unit touch (HID) events at info level.
- 0001: debug-level logging in release builds; kept for diagnosis builds, not applied.

## Car notes (2024 Kia Sportage, Canada)

- Wired-only CarPlay. With patches 0002 + 0003, wireless CarPlay works through the box (screen, audio and
  touch tested; Siri, calls and navigation not tested separately).
- The first pairing needs one tap on the car screen: the box shows the Bluetooth pairing confirmation
  and takes the next touch as "accept" (the box has no screen or button of its own). Later connections
  are automatic.
- Two iPhones are paired (added from Settings > General > CarPlay while the box is connected to the
  car). New phones can only pair while the box is connected to the car.
- Turning the phone's Wi-Fi off returns the car to the connection screen within about 10 s; with Wi-Fi
  back on CarPlay resumes by itself (0006–0008).
- Open: once, after an automatic reconnect, the touchscreen did not respond for the whole session; the
  next sessions were fine. Patch 0005 is in the image to catch it.
- If catplay exits, `u5a-catplay-run` saves a crash snapshot and restarts it (tested by killing it).
- Open, occasional: after reversing the car stayed on its own menu instead of returning to CarPlay (one
  tap brought CarPlay back). Log of that time: the car borrowed the screen (REAR_CAM), unborrowed it,
  the phone took it back and video resumed 0.16 s later (catplay tears the car-side screen stream down
  during a borrow and sets it up again), then 0.25 s after the unborrow the car sent Take
  (UserInitiated) itself. A repeat attempt returned to CarPlay normally. Compare with a good reverse
  from the logs before changing anything; one idea to check is whether the car gives up when the
  video is not back fast enough.

## Things that cost time

- SPI0 pins are PC0–PC5 **function 4** on V851S (the T113 code path uses other pins/functions).
- Boot0 leaves SPI0 configured for DMA; reset it through the CCU before use.
- A `reserved-memory` node in the DT stopped this kernel early; the boot report lives in SRAM instead.
- busybox 1.37 httpd: with CGI enabled but BASIC_AUTH disabled, `/` returns 404 (the appended
  index.html is truncated and never restored). BASIC_AUTH is enabled (no password configured).
- busybox `head -c` and `od -A` need FEATURE_FANCY_HEAD / DESKTOP; the scripts use `hexdump -e`.
- catplay logs to stderr and dumps every RTSP message at WARN, including a once-per-second feedback
  exchange: about 3.6 MB of RAM per hour unless filtered.
- The 5 GHz AP looked like WEP to Apple devices until the driver's TIM insertion was fixed.
