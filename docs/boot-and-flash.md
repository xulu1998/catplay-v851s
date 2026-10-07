# Boot chain, flash layout and recovery

## Boot chain

    BootROM -> stock Boot0 (NOR 0x0, unchanged; DRAM init)
            -> u5a-loader (in the TOC1 'u-boot' slot at NOR 0x10000, run at 0x42000000)
            -> zImage, DTB and EROFS root copied from NOR to DRAM, CRC32 checked
            -> Linux 7.2.7 (root=/dev/initrd rootfstype=erofs, init=/sbin/u5a-init)

The factory U-Boot is not used. It never booted a mainline kernel on this board, passes its own vendor
DTB, caps the ramdisk below 0x41800000 and writes its environment back to NOR on several paths.

**Boot0 → loader.** Boot0 loads the TOC1 package (`sunxi-package`, valid_len 0x58000, items `u-boot`
0x400/0x3c000 and `dtb` 0x3c400/0x1a5a7) and checks two stamp checksums (seed 0x5F0A6C39): the
package `add_sum` and the U-Boot head's own. u5a-loader keeps the factory U-Boot head layout
(`b 0x640`, magic `uboot`, checksum, length, run address 0x42000000); Boot0 writes its DRAM parameters
into bytes 0x30–0x4f8, so the code starts at 0x640. `loader/mkimage.py` copies the factory head and
fixes the checksum, `scripts/build-nor-image.py` recomputes `add_sum`.

**u5a-loader** (`loader/`, about 6 KiB, C and assembly):

1. Sets the Boot0 FEL flag (RTC GPR[2] 0x07090108 = 0x5aa5a55a) and arms a 16 s reset watchdog, so a
   hang anywhere from here on ends in FEL rather than a dead box. u5a-init clears both once Linux runs.
2. Identity-maps DRAM with the D-cache on (`mmu.c`). This halves the boot time.
3. Resets SPI0 through the CCU first (Boot0 leaves it in its own DMA configuration), then sets it up
   like xfel's V851 payload: PC0–PC5 function 4, READ 0x03, receive-only bursts, byte reads from RXD
   (32-bit reads of RXD hung).
4. Reads the boot table at NOR 0x470000 (magic `U5AB`, version 1, three entries of NOR offset,
   length, DRAM address, CRC32, then a CRC32 of the table) and copies zImage to 0x41800000, the DTB to
   0x43000000 and the root to 0x43400000, computing CRC32 while reading.
5. Any bad magic or CRC: report the failure stage and reset; Boot0 sees the flag and enters FEL.
6. Success: clean the caches, MMU and caches off, r0 = 0, r1 = ~0, r2 = DTB, jump to the zImage.

A boot report (`struct boot_report` in `loader/boot.c`: stage, per-image CRCs, timer ticks) is left in
SRAM at 0x3a000; read it with `devmem` from Linux. Measured: 6.22 s from loader start to the kernel for
13.7 MiB (11.6 s with the D-cache off).

The EROFS root is not unpacked: kernel patch 0013 lets `root=/dev/initrd` mount the image in place
from the reserved initrd memory, so binaries are paged from the compressed image.

## Flash layout

| NOR offset | Size | Content | Linux MTD |
| --- | --- | --- | --- |
| 0x000000 | 64 KiB | stock Boot0, **never written** by any script here | `u5a-loader` (read-only) |
| 0x010000 | 448 KiB | TOC1: u5a-loader in the `u-boot` item, factory `dtb` item kept | `u5a-loader` (read-only) |
| 0x080000 | max 0x3e0000 | zImage | `u5a-system` |
| 0x460000 | 64 KiB | DTB | `u5a-system` |
| 0x470000 | 64 KiB | boot table | `u5a-system` |
| 0x480000 | max 0xa80000 | root, EROFS lz4hc (about 9.4 MiB) | `u5a-system` |
| 0xf00000 | 1 MiB | /persist, JFFS2: settings, Bluetooth pairings, HomeKit identity, logs | `persist` |

`u5a-system` is writable only so the settings page can update the firmware (`flashcp`, which verifies
by reading back). The loader region is read-only in the DT, and the whole-flash MTD device is not
exposed. CONFIG_MTD_SPI_NOR_SWP_KEEP leaves the flash status register alone.

## Images

The same layout is built twice, differing only in the DT `bootargs` (`u5a.mode=`):

- **bench**: the USB port is a debug gadget (ACM shell + NCM network, 10.77.0.1). CatPlay runs, its car
  side is off. For development on a computer.
- **car**: the USB port belongs to the car (g_iphone, the CatPlay iPhone gadget). Debugging is over the
  box Wi-Fi (dropbear on 192.168.50.2, no root password). The 16 s watchdog is disarmed at once.

## Recovery

| Situation | Path |
| --- | --- |
| Bench image running, computer connected | `scripts/nor-install.sh <dir> --from-linux` sends the box to FEL over the ACM shell (GPR[2] flag + watchdog reset) and installs |
| Car image running | join the box Wi-Fi from a Mac; `scripts/recover-over-wifi.sh <home-ssid>` fetches the logs, sends the box to FEL over SSH and installs the bench image. `--logs-only` and `--ota <bundle>` do less |
| Settings page reachable | upload an OTA bundle (`out/u5a-ota-*.bin`) |
| Linux comes up but nothing is reachable | plug in, wait about 5 s, unplug; twice; plug in a third time: three boots shorter than 20 s send the box to FEL (u5a-init, needs a working /persist) |
| Kernel, DTB or root corrupt | the loader's CRC check fails and the box comes up in FEL |
| Back to factory | `scripts/nor-restore.sh` writes your own full dump back from 0x10000 (Boot0 is never touched) |

The factory pad short does **not** reach FEL once the loader is installed. Keep at least one software
path working before an install that could stop Linux from booting.

## Known issue: Bluetooth after a warm reset

After a watchdog (warm) reset the RTL8733BS Bluetooth core does not answer H5 sync again; Wi-Fi does.
Toggling PE8 for 3 s (through an mmc unbind) or PD20 did not reset it. Only a power cycle helps. The
firmware avoids warm resets in normal use: applying settings restarts the services only, and after a
firmware update the page asks to unplug and replug the box.
