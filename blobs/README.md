# blobs/: files you supply yourself

Nothing in this directory except this README is tracked by git. These files come from your own box
and are not redistributed here.

| File | What | How to get it |
| --- | --- | --- |
| `factory-flash.bin` | A full 16 MiB dump of **your** box's SPI NOR, taken before anything is written. The image builder copies Boot0 and the factory TOC1/U-Boot header from it; `scripts/nor-restore.sh` uses it to go back to factory. | Enter FEL with the factory firmware (pad short, docs/hardware.md), then `xfel spinor read 0 0x1000000 blobs/factory-flash.bin`. Keep a second copy somewhere safe. |
| `rtl8723fs_fw.bin` | Realtek Bluetooth firmware for the RTL8733BS | Factory customer partition (NOR 0x900000, squashfs): `firmware/rtlbt/rtl8723fs_fw`. Unpack the partition from the dump with `unsquashfs`. |
| `rtl8723fs_config.bin` | Its config file | Same place: `firmware/rtlbt/rtl8723fs_config` |

The image builder (`scripts/build-nor-image.py`) checks that `factory-flash.bin` starts with a valid Boot0 (`eGON.BT0`) and
the expected TOC1 layout before it builds anything.
