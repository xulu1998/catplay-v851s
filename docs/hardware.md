# Hardware

The board this port was developed and tested on. Facts come from the device and its factory flash
unless marked otherwise.

## The box

- Product: LY2734 "smartBox" (sold as U5A), a wired-to-wireless CarPlay adapter. Factory app version
  26051317.2734.2. Same OEM family ("LY", cpbox-abroad) as the ly5190/ly5166/ly5101 V821B boxes that
  upstream CatPlay supports.
- SoC: Allwinner V851S (sun8iw21p1), one Cortex-A7, ARMv7. The kernel uses the V853 compatible.
- RAM: 64 MiB DDR2 (`xfel ddr u5a` profile, 528 MHz). Linux reports about 58 MiB usable.
- Flash: 16 MiB SPI NOR, XTX, JEDEC ID 0x0b4018, SFDP.
- Radio: Realtek RTL8733BS combo. Wi-Fi on SDIO (mmc1), Bluetooth on UART2 (H5 / 3-wire).
- Apple MFi authentication coprocessor 2.0C on I2C (TWI3), answering at 0x10 and 0x11.
- One USB port (USB0, musb OTG). It powers the box and goes to the car (or to a computer).
- No usable debug UART without opening the box (UART0 on PH9/PH10, 115200 8N1).

## Peripheral map

From the factory U-Boot DTB (NOR 0x4c400), the factory /etc/profile and the customer partition.

| Function | Pins / bus | Notes |
| --- | --- | --- |
| Wi-Fi SDIO | mmc1, PE0–PE5, function 6 | 4-bit, 50 MHz, 3.3 V |
| Wi-Fi/BT chip enable | PE8 | mainline pwrseq reset-gpios, active low |
| 32 kHz to the radio | FANOUT0 from the RTC osc32k | internal RC (31250 Hz), LOSC_CTRL=0x4010 |
| Bluetooth UART | uart2, PE10–PE13, function 6 | `realtek,rtl8733bs-bt`, RTL8723FS firmware |
| BT reset (unused) | PD20 | not needed: H5 sync works with PE8 alone |
| MFi coprocessor | TWI3, PH13 SCL / PH14 SDA, function 5, 100 kHz | catplay `bus_offset = 3`, `dev_addr = 0x11` |
| GPIO expander | TWI3 0x20, NXP PCA9555 (factory DTB) | probably LEDs; does not ACK, unused |
| SPI0 (NOR) | PC0–PC5, **function 4** | the T113 sequence in xfel's source uses other pins; function 4 is from xfel's V851 payload |
| Debug UART0 | PH9 / PH10 | |

Useful registers: SPI0 at 0x04025000 (CCU clock 0x02001940, gate/reset 0x0200196c); watchdog at
0x020500a0 (CTRL 0xb0, CFG 0xb4, MODE 0xb8, SRST 0xa8; write 0x16aa0001 to SRST to reset); RTC GPR[2]
at 0x07090108.

## Factory flash layout

| Partition | Offset | Size |
| --- | --- | --- |
| uboot (Boot0 + U-Boot TOC1) | 0x000000 | 512 KiB |
| boot | 0x080000 | 2 MiB |
| recovery | 0x280000 | 2 MiB |
| rootfs (squashfs) | 0x480000 | 4.25 MiB |
| env | 0x8c0000 | 256 KiB |
| customer (squashfs) | 0x900000 | 4.5 MiB |
| private | 0xd80000 | 64 KiB |
| logo | 0xd90000 | 1 MiB |
| UDISK | 0xe90000 | 1.4375 MiB |

The factory system is Linux 4.9.191 (squashfs root, `init=/pseudo_init`) running the vendor app from
/mnt/customer/app. The Bluetooth firmware this port needs (`rtl8723fs_fw`, `rtl8723fs_config`) is in
the customer partition under `firmware/rtlbt/`.

## FEL (USB boot mode)

The BootROM's FEL mode is how the first install is done and how a broken install is repaired.

- With the factory firmware: unplug, short the pair of silver test pads, plug in, keep the short for
  3–5 s. `xfel version` must answer `AWUSBFEX ID=0x00188600(V851/V853)`. USB enumeration alone is not
  proof of FEL.
- **After this port is installed the pad short no longer works** (it seems to be read by the factory
  U-Boot, not the BootROM). Use one of the software paths instead (docs/boot-and-flash.md, Recovery).
