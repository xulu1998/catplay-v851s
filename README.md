# catplay-v851s

[中文说明](README.zh-CN.md)

A port of [CatPlay](https://github.com/catplay-labs/catplay), the open-source CarPlay implementation, to
wired-to-wireless CarPlay adapters built on the **Allwinner V851S** with a **Realtek RTL8733BS** radio.
The adapter plugs into a car that only has wired CarPlay; the iPhone connects to it wirelessly.

Developed and tested on one **LY2734 "smartBox" (U5A)** in a **2024 Kia Sportage**. Wireless CarPlay
works there: screen, audio and touch.

This is an independent port, not an official CatPlay release. It replaces the adapter's firmware. Read
the whole page before you write anything to a box.

## What is in here

| Path | What |
| --- | --- |
| `loader/` | u5a-loader: a small boot loader that sits where the factory U-Boot was, reads the kernel, DT and root from the SPI NOR (CRC-checked) and starts Linux |
| `kernel/` | patches for Linux 7.2.7, the RTL8733BS Wi-Fi driver and CatPlay's `g_iphone` gadget; the kernel config; the board device trees (bench and car) |
| `yocto/meta-u5a/` | Yocto layer for the upstream [catplay-firmware](https://github.com/catplay-labs/catplay-firmware) BSP: machine `v851s-rtl8733bs`, image `u5a-e28-image`, init, settings web page, firmware update, CatPlay patches |
| `scripts/` | fetch sources, build kernel / modules / images, install, restore, recover |
| `docs/` | [hardware](docs/hardware.md), [boot chain and flash layout](docs/boot-and-flash.md), [porting notes](docs/porting-notes.md), the [experiment log](docs/experiment-log.md), [upstream reports](docs/upstream/) |
| `blobs/` | files you take from your own box (factory flash dump, Bluetooth firmware); not in git |

## Features

- Boots from the box's own flash in about 6 s (loader to kernel), then CatPlay.
- Settings page on the phone: `http://192.168.50.2/` while connected to the box Wi-Fi. Wi-Fi name and
  password, Bluetooth name, 5 GHz channel, preferred iPhone.
- Firmware update from the same page (bundle checked by SHA-256 before anything is written; Boot0, the
  loader and your settings are never touched).
- Your own picture on the connection screen (`yocto/meta-u5a/recipes-apps/catplay/files/u5a-logo.jpg`).
- Several recovery paths that do not need to open the box (docs/boot-and-flash.md).

Default network: Wi-Fi `CatPlay-V851S`, password `catplay123`. Change it on the settings page.

## Status

| | |
| --- | --- |
| Boot from NOR, persistent settings and pairings | works |
| Wireless CarPlay, Kia Sportage 2024 (Hyundai Mobis D-Audio) | works (needs CatPlay patches 0002 + 0003) |
| Settings page, firmware update over Wi-Fi | works |
| First pairing | needs one tap on the car screen (Bluetooth pairing confirmation) |
| Bluetooth after a warm reset | does not come back until a power cycle (avoided by design) |
| Phone Wi-Fi off and on during CarPlay | reconnects by itself (CatPlay patches 0006–0008) |
| Phone arriving after the first minute | box keeps paging it (0006); not yet confirmed in the car |
| Touch after an automatic reconnect | failed once, worked every time since; under investigation |
| Other cars, other V851S boxes | untested |

## Building

You need: a Linux build host for Yocto (an aarch64 or x86_64 VM is fine: 16 GiB RAM + swap, 100 GiB
disk), `arm-none-eabi-gcc`, `dtc`, Python 3, [xfel](https://github.com/xboot/xfel). The kernel and
loader were built on macOS (Homebrew); on macOS also install GNU make, sed and findutils and put them
first in PATH, and `libelf`.

1. Put your files in `blobs/` (see [blobs/README.md](blobs/README.md)).
2. Sources and patches: `sh scripts/fetch-sources.sh`
3. Kernel and modules: `sh scripts/build-kernel.sh && sh scripts/build-modules.sh`
4. Root file system, on the Yocto host with this repository at the same path:
   `sh scripts/yocto-setup.sh`, then
   `cd ~/yocto/catplay-firmware && . openembedded-core/oe-init-build-env ~/yocto/build && bitbake u5a-e28-image`
5. Images: `sh scripts/build-images.sh <.../u5a-e28-image-v851s-rtl8733bs.rootfs.erofs-lz4hc>`
   gives `out/bench/`, `out/car/` and firmware update bundles `out/u5a-ota-*.bin`.

## Installing

**This replaces the firmware of the box. You can lose the box.** Keep your factory dump safe.

1. Box in FEL (first time: factory firmware, pad short, docs/hardware.md).
2. `sh scripts/nor-install.sh out/bench` (or `out/car`). It dumps the whole flash to `backups/` first,
   refuses to run if the first 64 KiB differ from the image, never writes Boot0, reads everything back
   and compares, then resets.
3. With the bench image the box shows up on the computer as a serial port and a network (10.77.0.1).
   With the car image, plug it into the car.

Later updates: the settings page, or `scripts/nor-install.sh out/car --from-linux` from a bench image.
Back to factory: `scripts/nor-restore.sh`.

## Credits

- [CatPlay](https://github.com/catplay-labs/catplay) and
  [catplay-firmware](https://github.com/catplay-labs/catplay-firmware): everything CarPlay. Kernel
  patches 0001–0013 (btrtl RTL8733BS, musb / USB PHY role switch, cdc-ncm, EROFS root in place) come
  from catplay-firmware's meta-sunxi (V821 port).
- [prototype-v851s-port](https://github.com/hbouhadji/prototype-v851s-port): V851S/V853 SoC support
  for mainline Linux.
- [RTL8733BS_WiFi_linux_v5.14.1.1-46](https://github.com/newbie-461/RTL8733BS_WiFi_linux_v5.14.1.1-46):
  the Wi-Fi driver.
- [xfel](https://github.com/xboot/xfel): FEL tool; its V851 SPI payload showed the SPI0 setup.

## License

GPL-2.0-only, see [LICENSE](LICENSE), the same license as CatPlay's recipes and the Linux kernel.

Not affiliated with Apple, CatPlay, Allwinner, Realtek or the adapter's maker. CarPlay and iPhone are
trademarks of Apple Inc.
