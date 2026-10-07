# Experiment log (historical)

The working log of the port (E01–E35; the entries are not in strict date order). It is kept for the reasoning and the
measurements. Paths in it refer to the original working repository (artifacts/, vendor/, build/,
scripts/stage1-*), most of which is not part of this repository; experiment scripts and the
intermediate images were dropped. The current design is in [boot-and-flash.md](boot-and-flash.md).


This file records experiments that materially changed our understanding. Its purpose is to prevent repeated tests and repeated hypotheses.

## E01 — Mainline Linux 7.2.7 RAM boot

Goal: prove the board can run a fully custom RAM Linux payload.

Result: PASS.

Observed Linux 7.2.7-v851s-ram-stage1, about 58 MiB usable RAM and USB ACM/NCM.

Proves FEL, DDR, CPU execution, Linux execution and USB gadget capability.

## E02 — Custom Linux 4.9 direct launch

Goal: directly launch a vendor-like 4.9 kernel.

Result: no reliable userspace marker.

Lesson: the factory 4.9 route requires more than a bare kernel branch.

## E03 — Exact factory kernel + stock DTB direct launch

Goal: determine whether only our custom kernel was wrong.

Result: no normal factory userspace/AP.

Conclusion: the vendor U-Boot handoff matters.

## E04 — Stock Boot0 from SRAM

Method:

- Boot0 staged at 0x43000000
- 68-byte relocator at 0x30000
- relocator copies to 0x20000 and executes

Result: PASS. Unpatched Boot0 reached the factory chain and the known smartBox AP.

Conclusion: preserve Boot0 as a compatibility layer.

## E05 — Live U-Boot comparison

Result: only 43 bytes / 19 runs differ between static U-Boot and Boot0-loaded RAM, all before offset 0x600.

Conclusion: Boot0 injects header/private parameters, not code patches.

## E06 — Late FEL after Boot0 then resume U-Boot

Result: mainline tolerated the late-FEL path, factory U-Boot did not reproduce normal boot.

Conclusion: native FEL cleanup changes state relevant to the factory U-Boot path.

## E07 — Minimal Boot0 -> U-Boot trampoline

Result: far better preservation of the stock handoff.

Conclusion: tiny post-Boot0 SRAM interposition is the correct style.

## E08 — Force-default-environment prototype

First failure: the hook used BL without preserving LR, so the instrumentation itself looped.

Second lesson: forcing default environment discarded vendor bootargs.

Conclusion: instrumentation bug plus wrong strategy. Do not use as primary path.

## E09 — Factory environment with RAM-only command interception

Method:

- saveenv behavior intercepted in RAM so the factory script follows its non-persistent branch;
- boot-partition reread intercepted in RAM so the preloaded image remains available;
- bootm command handler temporarily redirected to stock U-Boot efex.

Result: PASS; responsive FEL returned.

Proves:

    Boot0 -> U-Boot -> u5a_restore -> setargs_nor -> boot_normal -> bootm command dispatch

## E10 — Raw BootROM kernel-entry FEL probes

Result: unreliable. Device could enumerate as 1f3a:efe8 while xfel timed out. Host libusb reset could also time out.

Conclusion: direct BootROM return is not a safe success marker.

## E11 — Skip Boot0 DDR retraining

Goal: test the hypothesis that Boot0 DDR init destroys a preloaded boot image.

Result: no Linux gadget.

Later status: premise was directly disproven by E13.

## E12 — External gadget initramfs added to boot image

Artifact:

    artifacts/stage1/linux-4.9-stocklike-wifi-gcc6-v2.img

Result: no U5A RTL8733BS Probe enumeration.

Later reinterpretation: the factory U-Boot ramdisk path is vendor-specific, so this did not cleanly prove the kernel itself failed.

Final reinterpretation (E16/E17, offline): the vendor U-Boot accepts a cpio in the ramdisk field and passes it to Linux correctly. The payload itself was broken: its libc.so was truncated to 262144 bytes (sha256 prefix d3542d0695), so every dynamically linked binary, including busybox, could not run. The run gave no information about the kernel or handoff.

## E13 — Full DDR retention test

Script:

    scripts/stage1-retention-auto-launch-linux49.sh

Full 4.4 MiB image staged at:

    0x41800000
    0x42400000
    0x43400000
    0x43a00000

After full stock Boot0 DDR initialization, the images were read back and compared.

Result: PASS for all observed tested regions.

Auto-launch chose:

    stage434 @ 0x43400000

Linux gadget still did not appear.

Conclusion: DDR-retention theory is CLOSED.

The missing gadget is explained by the same truncated userspace as E12 (see E17), not by the handoff.

## E14 — Factory ramdisk inspection

Result: factory Android ramdisk is exactly 12 bytes containing the text ramdisk.img followed by a newline.

U-Boot contains init_boot and related vendor ramdisk logic.

Conclusion: vendor ramdisk semantics are now the highest-priority offline target.

## E15 — Prepared pre-kernel checkpoint / exact-stock-kernel control

Status: PREPARED, NOT RUN as of 2026-10-05.

Script:

    scripts/stage1-prekernel-checkpoint-then-stockcontrol.sh

Phase A would redirect the point immediately after U-Boot prints Starting kernel to stock U-Boot efex.

Phase B would run the exact factory 4.9.191 / GCC 6.4.1 kernel with the same diagnostic userspace as a control.

Re-evaluate after vendor ramdisk analysis instead of running automatically.

Status 2026-10-06: RETIRED, do not run.

- Phase B cannot work: the factory kernel has no CONFIG_BLK_DEV_INITRD, so it ignores any initrd. Its control image also carried the truncated libc.
- Phase A does not change the next decision. If E17 fails, Plan B follows either way. Its efex return after the pre-kernel cleanup is also unproven and could cost an extra physical FEL entry.

## E16 — Offline reverse engineering of the vendor ramdisk path

Status: DONE (offline). Details in docs/VENDOR-BOOT-RE.md §6.

Result: on this device the boot.img ramdisk is always used. init_boot is an absent partition name and vendor_boot applies only to header v3+. The ramdisk is copied to load_ramdisk_addr (default hdr->ramdisk_addr 0x41000000). linux,initrd-start/end are written into the U-Boot-embedded DTB, and that DTB is copied to 0x41800000. A checksum over the copied ramdisk is checked before the jump; a mismatch resets the board. `ramdisk.img\n` is a 12-byte placeholder. The factory kernel has no initrd support and boots squashfs from mtdblock3.

Conclusion: open hypotheses 1 and 3 (vendor ramdisk semantics, FDT/initrd layout) are CLOSED for images that respect the layout constraints.

## E17 — Root cause of the missing 4.9 userspace, and the corrected probe

Offline finding: reference/rootfs-stock was extracted incorrectly. Only the first 256 KiB xz block of each file was kept and fragments were lost. 11 files are wrong: libc.so is 262144 bytes instead of 438965, and libgcc_s.so.1 and 8733bs.ko are 0 bytes. The same truncated libc.so is in every Linux 4.9 diagnostic initramfs built so far, embedded or external. Under qemu-user the old libraries die with SIGBUS (exit 135) and correctly unsquashed libraries print USERSPACE_OK.

The former handoff note (artifact naming section) was wrong: gcc6-v1 did embed the correct /init. The marker search failed only because the initramfs is gzip-compressed inside vmlinux.

Corrected artifact: artifacts/stage1/linux49-embedded-probe-v1/, built by scripts/build-linux49-embedded-probe.sh.

- Libraries come from a fresh unsquashfs of the mtd3 backup (228/228 files). The ELF, NEEDED and qemu checks, `sh -n init` and the applet check all pass.
- The GCC6 4.9.191 kernel was rebuilt in a copied O= directory. The .config diff is only CONFIG_INITRAMFS_SOURCE. The embedded cpio is verified byte-for-byte against the staged root.
- boot.img starts from the factory mtd1 header with only kernel_size and the SHA1 id changed. It keeps the factory `ramdisk.img\n` placeholder.
- Footprint check: decompressor worst case ends at about 0x40ec3ba0, below 0x41000000.
- stage434-copy.bin is stage434.bin with only the copy length changed (0x466800 -> 0x430800).

Hardware run: scripts/stage1-linux49-embedded-probe.sh (U5A_APPROVED=1). Status: RUN 2026-10-06 06:47, result FAIL.

Pre-declared outcomes:

- PASS: USB device "U5A RTL8733BS Probe", serial "U5A-L49-EMB-V1", enumerates within 90 s. Milestone 1 is reached on the vendor 4.9 path. Next, Wi-Fi diagnostics over ttyGS0 / usb0.
- FAIL: no such device. With userspace validated offline, the GCC6 kernel or handoff is at fault. Switch to Plan B (mainline 7.2.7 + RTL8733BS) and do not probe 4.9 further.

Observed:

- Healthy FEL, xfel ddr u5a, all four payloads verified by readback (RAM_PAYLOAD_VERIFIED), exec 0x30000 at 06:47:34.
- No probe gadget within 90 s.
- Afterwards the host still showed 1f3a:efe8, and `xfel version` timed out. Its IOUSB sessionID dates the enumeration to 06:47:15, before the launch. It is the stale BootROM FEL enumeration.
- The USB device never disconnected after launch. There was no SoC reset, so not the U-Boot "ramdisk checksum bad -> reset" path, and Linux never initialised the UDC.

Host topology: the board was connected through the same USB hub/dock as every earlier experiment (the MacBook has no USB-A port). E01 (mainline gadget re-enumeration) and E09 (efex return) worked through it, so the dock is not a variable.

Conclusion: the chain stops silently somewhere between Boot0 and early Linux 4.9, before the USB gadget. Without UART it cannot be localised further. As pre-declared: vendor 4.9 handoff work STOPS; Plan B starts.

**INVALIDATED 2026-10-06 07:20 (see E18).** The NOR env was not the factory env during this run. It held only `boot_partition=boot`, `bootcmd=bootm 40007800` and `fdtcontroladdr=42b77e70`, so there were no bootargs. The kernel then falls back to its built-in CONFIG_CMDLINE, which contains `earlyprintk=sunxi-uart,0x05000000`; the V851S UART0 is at 0x02500000. An early printk to a wrong MMIO address explains a silent stop without reset. The decision to go to Plan B is withdrawn. E13 may have been affected the same way if the env was already broken then.

## E18 — Board stopped booting normally; NOR env found overwritten (2026-10-06)

Symptom: after the E17 power cycle there was no LED, no smartBox AP and no USB device. The last normal boot the user saw was on the evening of 2026-10-05.

Method: one physical FEL entry and a read-only full NOR dump with scripts/readonly-nor-dump-compare.sh, saved as artifacts/recovery/nor-dump-20261006-071601.bin.

Result:

- Boot0/U-Boot, boot, recovery, rootfs, private and logo are byte-identical to the factory backup.
- customer and UDISK differ only by the factory firmware's own runtime data, the same as the 10-05 pre-repair dump.
- The env partition (both copies, valid CRC) held only the three variables above. That matches artifacts/stage1/uboot-ram-bootm-v1/default_env_patch.bin (E08-style forced default env, 2026-10-05 21:24–22:17), which was evidently persisted by U-Boot during that run. The stage434 patch only neuters the saveenv command, not internal env_save calls.

Repair, with explicit user approval: wrote the factory env partition backup (sha256 49d23a80…, identical to factory full backup at 0x8c0000) to 0x8c0000–0x900000. Readback is byte-identical. No other partition was touched.

Verified 2026-10-06 07:22: after a plain power cycle the factory firmware boots again (red LED blinking, smartBox AP visible).

Lessons:

1. Before any vendor-handoff experiment, verify the on-NOR env read-only. Do not assume it.
2. Any kernel booted without U-Boot bootargs must have a correct CONFIG_CMDLINE. The GCC6 config's earlyprintk address 0x05000000 is wrong for V851S.
3. Any experiment that forces or patches the default env must also block internal env_save, not only the saveenv command.

Offline follow-up (U-Boot env write paths). env_save() is at 0x42015e74 and has exactly four direct callers:

- 0x42007a72: the saveenv command.
- 0x42002f44: OTA path, only when ly_boot_mode=update. The same function's branch at 0x4200305e auto-saves `boot_partition=boot` when boot_partition is missing. This is how the E08 forced default env got persisted.
- 0x4201670a: env load, when the main/backup copies are valid but their CRC words differ ("not synchronized, now to synchronize"). The factory backup itself has unsynchronised copies (CRC 0x9b44f5ed vs 0x964c5a32), so stock U-Boot may write NOR on a normal boot.
- 0x42016750: env load, backup CRC bad ("Now update backup env").

update_bootcmd (0x42002b8c) only calls env_set; it rewrites `run setargs_nand boot_normal` to `setargs_nor` for SPI NOR and never saves.

## E19 — Valid rerun of E17

Status: RUN 2026-10-06 07:31–07:34, result **FAIL (valid)**.

Observed:

- NOR precheck passed. The snapshot artifacts/recovery/nor-pre-e19-20261006-073136.bin has all immutable partitions identical to factory and the main and backup env with all 38 variables equal to factory.
- Payload readback was verified and the launch happened at 07:32:31.
- No probe gadget within 90 s. The host kept the stale BootROM FEL enumeration from 07:31:23: no disconnect, so no SoC reset and no Linux UDC init. This is the same signature as E17.

Conclusion: with a verified factory env and factory bootargs, the GCC6 4.9.191 kernel with a verified embedded userspace still does not reach USB gadget init. The stop point lies between Boot0 and early kernel; no UART is available to localise it. As pre-declared, the vendor 4.9 handoff route is STOPPED and Plan B is active.

Script: `U5A_APPROVED=1 sh scripts/stage1-linux49-embedded-probe.sh`

Differences from E17:

1. Read-only full NOR snapshot and `u5a_probe_check.py nor-precheck` before launch. It refuses unless the immutable partitions (boot0/uboot, boot, recovery, rootfs, private, logo) are byte-identical to the factory backup and the main env's boot-critical variables equal the factory values. Tested offline: the factory backup passes; the 10-06 broken env and the 10-05 u5a_restore env are refused.
2. Trampoline stage434-copy-envsave.bin retargets the existing `movs r0,#1; bx lr` patch from the saveenv command (0x42007a70) to env_save() (0x42015e74). This blocks all four writers above, and saveenv still fails. The change is one literal; the tool verifies the env_save prologue in u-boot.bin.

boot.img, kernel and userspace are unchanged from E17.

Pre-declared outcomes:

- PASS: "U5A RTL8733BS Probe" / U5A-L49-EMB-V1 enumerates within 90 s, giving Milestone 1 on vendor 4.9.
- FAIL with precheck passed: vendor 4.9 route stops, Plan B.
- Precheck refused: nothing launched, offline analysis.

## E20 — Plan B: mainline 7.2.7 + RTL8733BS over SDIO

Status: RUN 2026-10-06 07:56. Formally outcome B (no SDIO device), but this is a **software artifact, not hardware evidence**. The Wi-Fi chip was never powered.

Observed (log artifacts/logs/e20-20261006-075619.log, live follow-up artifacts/logs/live.log):

- The Wi-Fi kernel, gadget, ACM shell and NCM network all came up within 2 s. This confirms the 7.2.7-wifi kernel and DT boot.
- `devices_deferred`: wifi-pwrseq was deferred ("reason unknown"), so 4021000.mmc was deferred with "supplier wifi-pwrseq not ready". No mmc host existed, PE0–PE8 stayed UNCLAIMED, and fanout0 stayed off.
  - Root cause: CONFIG_SUN6I_RTC_CCU was not set. The rtc (`allwinner,sun50i-r329-rtc`) bound to the legacy sun6i-rtc driver, which registers no clocks, so `osc32k` (rtc index 0) did not exist. The pwrseq `assigned-clock-parents = <&rtc 0>` could never resolve.
- `insmod: can't read /lib/modules/8733bs.ko`: the root had no /lib at all.
  - Root cause: the wifi-v1 cpio has `lib/modules` and the .ko but no `lib` directory entry. The kernel unpacker does not create missing parents and silently dropped both entries. My cpio self-check did not model this.
- The live board was used to load the module from /tmp, after an nc transfer with sha256 verified. Result: `RTW: module init ret=0`, and the sdio driver `rtl8733bs` registered. Module load on this kernel is therefore proven.
- PE8 was re-verified against the factory DTB embedded in U-Boot (NOR 0x4c400): `chip_en = <&pio 4 8 …>` (PE8), active high, no wlan_regon. vendor/prototype-v851s-port/analyse-v851s/stock-full.dts (PE9 + PA11) is from a different board config; do not use it.
- RTC LOSC_CTRL=0x4010: the 32 kHz source is the internal RC. The factory DTB declares an ext_losc.

## E21 — E20 rerun with both software faults fixed

Status: RUN 2026-10-06 08:08. Formally outcome B, then **Milestone 2 PASS** in the same session after a live fix. Logs: artifacts/logs/e21-20261006-080825.log and live.log.

Observed:

- Both E20 fixes worked: devices_deferred was empty, the mmc1 host existed (mmc0), and PE0–PE5 were sdc1 with pull-up.
  - PE8 was claimed by pwrseq, and osc32k = 31250 Hz (internal RC) fed fanout0.
  - The 8733bs module was present and loaded (ret=0).
- The card answered CMD5. Then: "card claims to support voltages below defined range", "no support for card's volts", "error -22 whilst initialising SDIO card".
  - Root cause: the DT has no vmmc-supply, so sunxi-mmc leaves `ocr_avail = 0` (logged live: 0x00000000) and the OCR intersection is always empty. This is not a hardware problem.
- Live fix without FEL: kernel/u5a_mmc_ocr (a RAM-only module) set ocr_avail = 0x00300000 (3.2–3.4 V), cleared rescan_entered and called mmc_detect_change. Result:
  - `mmc0: new high speed SDIO card at address 0001`, SDIO 024c:b733.
  - Bus: 50 MHz, 4-bit, 3.3 V signalling, vdd 3.3–3.4 V.
  - Chip: RTL8733B U4 1T1R, eFuse read OK, firmware downloaded from the array (FW 1.28, 119544 bytes), MAC 68:8f:c9:xx:xx:xb.
  - **wlan0 created**; `ip link set wlan0 up` succeeded.
  - Site survey (`echo scan > /proc/net/rtl8733bs/wlan0/survey_info`) listed 13 BSS on 2.4 GHz (ch1/6/11) and 5 GHz (ch153/157), RSSI −57…−94. Examples: xl5g, <home Wi-Fi>, BELL819.

Conclusion: the mainline 7.2.7 + ported RTL8733BS stack works on this board. The permanent fix is DT-only (see E22).

## E22 — DT fix for the E21 OCR problem (clean confirmation run)

Status: RUN 2026-10-06 08:19, **outcome D — PASS** (log artifacts/logs/e22-20261006-081917.log).

Observed, with no helper module:

- At boot (0.93 s): `mmc0: new high speed SDIO card at address 0001`, with no OCR warnings.
- insmod: firmware downloaded (FW 1.28) and wlan0 created (MAC 68:8f:c9:xx:xx:xb).
- IFUP_RC=0, and the link is UP with NO-CARRIER (not associated yet).
- The scan listed 15 BSS on 2.4 GHz (ch 1/6/11) and 5 GHz (ch 153/157).

The E22 package is the reference baseline for the Wi-Fi userspace phase.

Originally optional: E21 had already proved the Wi-Fi path. Script: `U5A_APPROVED=1 sh scripts/stage1-mainline-7.2.7-wifi-e22.sh`

- The only change from E21 is the DTB. It adds root node `reg-vcc3v3` (regulator-fixed, 3.3 V, always-on), and mmc1 gets `vmmc-supply` and `vqmmc-supply` pointing at it. zImage and initramfs are identical to E21, and the gadget serial stays U5A-720-WIFI-E21. The source DTS sun8i-v851s-u5a-wifi-64m.dts is updated the same way.
- The session tool now also runs a scan step.
- Expected: outcome D, with no helper module (wlan0 plus scan results).

## E23 — Live STA association (on the running E22 board, no FEL)

Status: RUN 2026-10-06 08:32, **PASS**. Script: `U5A_WIFI_SSID=xl5g sh scripts/live-wifi-sta-test.sh`. The first attempt failed with PUSH_MISMATCH: the board-side background nc was killed mid-transfer (160768 of 1124956 bytes) and could also steal tty input. Pushes now use board `wget` from a Mac http.server bound to 10.77.0.2, with sha256 verified.

Result:

- xl5g at 2437 MHz, HT40, WPA2-PSK CCMP: COMPLETED, RSSI −48, LINKSPEED 150.
- DHCP gave 192.168.2.132; default route via 192.168.2.1.
- Pings from the board: gateway ~3 ms, 8.8.8.8 ~8.6 ms. Mac → board over Wi-Fi OK.
- Hostname resolution in static-glibc busybox wget fails (NSS); nslookup works.

## E24 — CatPlay feasibility for this board (offline research)

Status: DONE 2026-10-06 08:40–09:00, offline only. The full analysis and plan are in docs/CATPLAY-PORT.md.

Question: can a GitHub third-party firmware give stable wireless CarPlay on this board in a 2024 Kia Sportage (wired-only head unit)?

Findings:

- CatPlay (catplay-labs/catplay, v0.10.0) is the only open dual-role implementation. Its stable ports are X1600 + AIC8800 and V821B + RTL8733BS (RISC-V). There is no build for V851S + RTL8733BS, and the V821B image cannot run on ARMv7.
- The board meets CatPlay's hardware needs. Factory /etc/profile has `LY_MFI_I2C_BUS=3`: the MFi chip is on TWI3 (PH13/PH14), which shares the bus with a PCA9555 at 0x20. BT is on uart2 (PE10–PE13). The customer partition ships rtl8723fs_fw/config, the same BT firmware CatPlay uses for RTL8733BS.
- The upstream V821 stack is mainline 7.x + RTL8733BS + hci_uart H5/btrtl + hostapd + bluez + the g_iphone kernel module. That is closest to our proven 7.2.7 + RTL8733BS base. ARMv7 is already a build target in the BSP (imx6ul-c2a machines).
- DiPlay (shihabal3amri/DiPlay) is an Android head-unit receiver APK. It is not applicable.
- In-car testing needs the box to boot from NOR, because its single USB port goes to the car. Writing NOR needs explicit approval; pad-short FEL plus the full backup is the recovery path.

Decision (user): port CatPlay. Next is P1 in CATPLAY-PORT.md (BT, MFi and USB kernel/DT work offline, then hardware run E25).

## E25 — CatPlay P1: Bluetooth (uart2 H5) and MFi bus (TWI3), Wi-Fi regression

Status: RUN 2026-10-06 09:11, **PASS on all three in substance** (log artifacts/logs/e25-20261006-091142.log; live follow-up in artifacts/logs/live.log). Script: `U5A_APPROVED=1 sh scripts/stage1-mainline-7.2.7-bt-e25.sh`. Package: artifacts/stage1/mainline-7.2.7-bt-e25/ (SHA256SUMS inside).

Result:

- Boot: gadget up 3 s after exec; healthy FEL beforehand; all four payloads read back equal.
- **BT: B+.** `serial serial0: tty port ttyS2 registered` (serdev bound), hci_uart H5 → `RTL: examining hci_ver=08 hci_rev=000f lmp_subver=8723`, rtl8723fs_fw.bin + config loaded (cfg_sz 41, total 28398), `RTL: fw version 0xd5a8776b`, hci0 created under the uart2 serdev. No PD20 toggle needed (answers open question 2).
- **MFi: M+ (the session line said FAIL, which was a probe-script bug).** `u5a-bt-probe` looked for /sys/class/i2c-adapter, which no longer exists on 7.x, so it printed `MFI_RESULT=FAIL no_i2c3_adapter`. Live on the same boot: mv64xxx bound 2502c00.i2c, /dev/i2c-3 present, clock bus-i2c3 on. `i2cdetect -y -r 3` shows 0x10 and 0x11 only. Registers 0x00–0x07 at both addresses: `05 01 02 00 00 00 02 00` (device version 0x05, firmware 0x01, auth protocol 2.0, device ID 0x00000200: Apple MFi CP 2.0C). Certificate length (reg 0x30) 0x038c = 908 bytes and certificate serial (reg 0x4e) `2222AA180511AA06AA5392AA151525` are identical at both addresses: one chip, answering on both. Use 0x11 (as upstream V821). The PCA9555 at 0x20 does not ACK in this state.
- **Wi-Fi: no regression.** wlan0, IFUP_RC=0, scan 15 BSS as in E22. The `Incorrect netdev->dev_addr` WARN at ifup is pre-existing (also in the E22 log) and harmless.
- Probe fix: userspace/mainline-bt-e25/u5a-bt-probe now finds the bus via /sys/bus/platform/devices/2502c00.i2c/i2c-* (checked live, BUS=3). The E25 initramfs is left as run; the fix goes into the next package.

Conclusion: P1 Bluetooth and MFi are proven on this board. Next is E26 (USB role switch + g_iphone).

Hypothesis: on the E22 base, enabling uart2 with an H5 serdev child and TWI3 brings up hci0 with the rtl8723fs firmware and makes the MFi chip answer on bus 3, without breaking Wi-Fi.

What changed from E22 (nothing else):

- Kernel: the same 7.2.7 tree plus patch kernel/patches-7.2.7/0001 (btrtl/hci_h5 RTL8733BS: compatible `realtek,rtl8733bs-bt`, rtl8723fs firmware, SKIP_REG16 quirk). Config adds 30 lines vs E22 (backup build/plan-b/config-e22.bak): BT=y with BR/EDR, LE and RFCOMM; BT_HCIUART=m with SERDEV, H4, 3WIRE and RTL; BT_RTL=m; SERIAL_DEV_BUS; I2C_MV64XXX and I2C_CHARDEV; ECDH crypto. Still no SPI/MTD driver.
- DT: uart2 (0x2500800) okay on PE10–PE13 mux 6 with pull-up, `uart-has-rtscts`, child `bluetooth { compatible = "realtek,rtl8733bs-bt"; }`; i2c3 (0x2502c00) okay on PH13/PH14 mux 5 with pull-up at 100 kHz; aliases serial2 and i2c3; initrd-end 0x43a374bb. The source DTS sun8i-v851s-u5a-wifi-64m.dts is updated the same way (checked equal after compilation, apart from phandle numbering).
- Initramfs (E22 + files): new /init (gadget serial U5A-720-BT-E25, boot state also runs the BT probe), /bin/u5a-bt-probe, /lib/modules/{hci_uart,btrtl,crc-ccitt}.ko, /lib/firmware/rtl_bt/rtl8723fs_{fw,config}.bin from the customer partition. tools/u5a_probe_check.py `cpio-patch` now creates missing parent directories for added files.
- USB role switch patches (0002–0011) are NOT in E25; they come in E26, so a gadget regression cannot confound this run.

Session order (tools/u5a_serial_session.py step set `e25`): boot state, `u5a-bt-probe state BEFORE`, `mfi` (i2cdetect bus 3; reg 0x00–0x07 read at 0x10 and 0x11, 5 tries each; PCA9555 0x20), `bt` (insmod crc-ccitt, btrtl, hci_uart; wait for hci0 and the `RTL: fw version` line), Wi-Fi insmod, ifup and scan, `state AFTER`, dmesg, `result`. BT is tested before Wi-Fi insmod; the shared chip enable PE8 is already high from the mmc1 pwrseq at boot.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| A | no gadget within 60 s | the BT/I2C kernel or DT stops boot; offline analysis |
| L | device lost during a step | crash; log kept up to the loss |
| M+ | `MFI_RESULT=PASS addr=0x1X` | MFi chip answers; address goes into catplay.conf `[mfi.i2c]` |
| M− bus_ok_no_mfi | other devices ACK (e.g. 0x20) but not 0x10/0x11 | chip needs a reset/power line or another address; check the i2cdetect map |
| M− bus_no_ack | nothing ACKs | pinmux/pull-up/clock wrong; compare the pinmux dump with the factory DTB |
| M− no_i2c3_adapter | no adapter at 2502c00 | driver/DT binding problem |
| B+ | `BT_RESULT=PASS hci0_fw_loaded` | BT controller ready for bluez (P3) |
| B− no_hci0 | hci_uart did not create hci0 | serdev binding or module load; dmesg |
| B− hci0_setup_incomplete | hci0 exists, firmware not confirmed | H5 sync/baud, PD20 reset, or firmware; dmesg |
| W− | `WIFI_RESULT=FAIL no_wlan0` | regression vs E22 |

Full PASS is `RESULT=PASS mfi_bt_wifi`. A partial result is still useful: each line is diagnosed live on the running board, without another FEL entry.

## E26 — CatPlay P1: car-side USB (musb role switch and g_iphone)

Status: RUN 2026-10-06 09:48, **PASS on all three hypotheses** (log artifacts/logs/e26-20261006-095023.log; the first log e26-20261006-094843.log is the false outcome A below). Script: `U5A_APPROVED=1 sh scripts/stage1-mainline-7.2.7-usb-e26.sh` (`U5A_E26_RESUME=1` continues on an already running board without FEL). Package: artifacts/stage1/mainline-7.2.7-usb-e26/ (SHA256SUMS inside).

Result:

- False outcome A, runner bug: the board booted and enumerated as "U5A RAM USB Role Probe" / U5A-720-USB-E26, but macOS named the port after the USB location (/dev/cu.usbmodem11301), not the serial as in E25, so the runner's tty match failed. Fixed (the probe is the only usbmodem device) and resumed on the same boot with `U5A_E26_RESUME=1`; no second FEL entry.
- Regression: MFI PASS, BT PASS (hci0, firmware loaded), WIFI PASS. Hypothesis 1 holds: DUAL_ROLE + `usb-role-switch` boot with ROLE=device and the ACM/NCM gadget configured.
- **Host role (H+):** SET_HOST_RC=0 → `phy-4100400.phy.0: Changing dr_mode to 1`, `ehci-platform 4101000.usb: USB 2.0 started, EHCI 1.00` (bus 1), `ohci-platform 4101400.usb` (bus 2); both bound; ROLE=host. The ACM port left the Mac 3 s after the cycle started.
- **Device role (D+):** SET_DEVICE_RC=0 → both HCDs removed and buses deregistered, `Changing dr_mode to 2`, ROLE=device. The still-bound ACM gadget re-enumerated on the Mac 12 s after it left. The legacy V853 PHY path works for both transitions; no `explicit_role` quirk needed.
- **g_iphone (I+):** all insmod/create/serial/udc/bind steps rc=0. dmesg: `initial gadget bind with udc_name 'musb-hdrc.2.auto' rs_name '4100000.usb'`, `setting usb role: /sys/class/usb_role/4100000.usb-role-switch/role -> device` (the role_switch_name patch works), `driver binding 4 configurations`. The Mac listed "iPhone", idVendor 1452 (0x05ac), idProduct 4776 (0x12a8), serial 00008130000E044E384B1D3AE26E26E26E26E26E, high speed, 3 s after the bind. macOS then sent Apple vendor request 0x40/0x40 (`Power Capability offered: 1000mA`) and selected a configuration; status `enabled`, UDC state configured.
- **Hand-back (J+):** unbind, remove, configfs rebind rc=0; the ACM port was back 26 s after the iphone cycle began.
- No WARN, Oops or BUG in the logs.

Conclusion: P1 is complete. All car-facing hardware mechanics CatPlay needs work on this SoC under 7.2.7: BT, MFi, Wi-Fi, USB device↔host role switch, and the g_iphone identity. What remains for the car side is the real head-unit flow (iAP2 role-switch request, NCM in host role), which needs catplay_c2a (P3) and a head unit (P4/P5).

Why it matters: in CarPlay the head unit starts as USB host, then asks the "iPhone" to swap roles; the box must become USB host (EHCI/OHCI) and talk NCM + iAP2 to the car's device side. g_iphone does the device half and triggers the swap through /sys/class/usb_role.

Hypotheses (one package, checked in order; each later step only runs if the ACM port came back):

1. With MUSB_DUAL_ROLE + `usb-role-switch`, boot and the ACM/NCM gadget work as before.
2. `host` on the role switch instantiates EHCI0/OHCI0 on PHY0 (they bind and register a USB bus); `device` removes them and the still-bound ACM gadget re-enumerates on the Mac.
3. g_iphone, bound to the same UDC, enumerates on the Mac as Apple 05ac:12a8 with our serial.

What changed from E25:

- Kernel: patches kernel/patches-7.2.7/0002–0012 applied (musb-sunxi optional clocks/resets, V821 support, userspace role switch, PHY hand-off to linked HCDs; the six phy-sun4i-usb VCBUS/V821 patches, which only take effect for `vcbus`/`explicit_role` configs, so V853 keeps the legacy detect worker; cdc-ncm head-unit fix). Config (backup build/plan-b/config-e25.bak): USB=y, USB_MUSB_DUAL_ROLE (was GADGET), EHCI/OHCI HCD + PLATFORM, USB_ROLE_SWITCH, USBNET + CDC_NCM + CDCETHER. zImage 3424800 bytes.
- Code reading for V853 (legacy PHY path): on `host`, the glue quiesces MUSB and calls phy_exit; EHCI's phy_init re-queues the PHY detect worker, which with dr_mode HOST routes PHY0 to the HCI side (`phy0_dual_route`). On `device`, the reverse. This is the part E26 proves.
- DT: usb@4100000 gets `usb-role-switch`, `#address-cells/#size-cells/ranges`, and EHCI0 (0x4101000) and OHCI0 (0x4101400) moved inside it as children with no status (the glue creates them only in host role). The source DTS is updated the same way (`/delete-node/ &ehci0; &ohci0;`); compiled outputs match.
- g_iphone: CatPlay's module maps UDC `musb-hdrc.1.auto` to the V821 role switch `44100000.usb`. On this board the UDC is `musb-hdrc.2.auto` and the role switch is `4100000.usb-role-switch`. Patch kernel/patches-catplay/0001 adds module parameter `role_switch_name` (we pass `4100000.usb`; later via modprobe.d). Built out of tree from build/g_iphone-7.2.7/b: g_iphone.ko, iap2_char.ko, iap2_scan.ko.
- 8733bs.ko rebuilt for the new config. The build must pass `CONFIG_BR_EXT=n` (the bridge extension does not compile against 7.x uapi `pppoe_hdr`); flags then match the E22 build.
- Initramfs (E25 + files): /init (serial U5A-720-USB-E26), fixed u5a-bt-probe, new /bin/u5a-usb-probe, the three CatPlay modules, rebuilt 8733bs.ko.

Session plan (three sessions, because the cycles drop the ACM port): e26a: boot state, BT/MFi/Wi-Fi regression, start the detached role cycle (wait 3 s, `host`, 6 s, record, `device`, 8 s, record). The host watches the ACM port leave and return. e26b: read the role log, start the detached iphone cycle (unbind configfs gadget, insmod iap2_char, iap2_scan, g_iphone role_switch_name=4100000.usb, create iphone0, serial 00008130000E044E384B1D3AE26E26E26E26E26E, bind; 20 s; record; unbind, remove, rebind configfs). The host watches for the Apple device with that serial and dumps its ioreg descriptor fields, then waits for ACM. e26c: read the iphone log, dmesg, results.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| A | no ACM at boot | DUAL_ROLE / role-switch kernel or DT breaks boot or the gadget; offline |
| regression | MFI/BT/WIFI line not PASS | config change broke a proven layer |
| H+ | `ROLE_HOST_RESULT=PASS ehci_ohci_bound` | PHY0 host path works |
| H− hcd_present_not_bound / no_hcd | EHCI/OHCI not created or not bound | DT child nodes, clocks/resets, or PHY routing; dmesg in role log |
| D+ | ACM back after the role cycle | host→device restores the gadget |
| D− | ACM not back in 60 s | device return broken; power-cycle; only the host timeline remains |
| I+ | Mac lists 05ac:12a8 with the E26 serial | g_iphone enumerates as an iPhone |
| I− | no Apple device | g_iphone bind/descriptor problem; iphone log |
| J+/J− | ACM back / not back after the iphone cycle | clean hand-back between gadgets |

A Mac host cannot test the role swap with a real head unit; that is P4/P5. E26 only proves the mechanics on this SoC.

## E35 — Car: touchscreen dead after an automatic reconnect (intermittent)

Run 1 (build 002413, second connection, automatic reconnect): CarPlay home screen appeared, video and audio fine, no touch input at all. The saved snapshot only had the first ~30 s of the catplay log (64 KiB head; the RTSP /feedback dump fills it), so the touch period was not recorded. Not caused by the pairing-tap handling: that code was never changed (the overlay consumes at most one touch per pending BT pairing request).

Changes for diagnosis (builds 012204 → 014748 → 015736, installed in the car box over Wi-Fi with the settings page OTA): catplay patch 0004 (info log of HID events: first 30, then every 200th, with car ts → decoded → iPhone ts, and overlay consumption); catplay output filtered by u5a-catplay-run (periodic /feedback dumps and per-touch lines dropped, ~17x less; rotation at 2 MB, it used to grow ~3.6 MB/h in RAM); snapshots at 10/30/60/120/300 s then every 5 min with a 256 KiB tail and a whole-session list of HID lines and errors. Bug found on the way: catplay logs to stderr, the first filter build only piped stdout (empty log), fixed in 014748.

Run 2 (build 014748, automatic reconnect): everything worked, touch included. Log: phone connected 3.9 s after start; more than 200 HID events by 30 s, every one proxied and answered 200 by the iPhone; timestamp translation sane (car ts 272528215638 → 35.22 s → iPhone ts 218316220218112).

Status: intermittent, cause unknown. The diagnosis build stays in the car; when it happens again, fetch /persist/log/snap-N.log (the "touch (HID) and errors" section).

## E34 — P5: customisation, settings page and firmware update over Wi-Fi (bench, NOR)

Goal: the user's requests after E33: cat logo on the CarPlay screen, Wi-Fi/BT name "the owner's Carplay", a settings web page on the phone, a preferred phone, firmware update over Wi-Fi; plus a faster loader.

Images: rootfs builds 20261007001215 (NOR install, INSTALL_VERIFIED 20:16) and 20261007002413 (installed by the OTA itself). Loader with identity MMU + D-cache: 6.22 s from loader start to kernel (was 11.6 s).

Bugs found on the bench and fixed:

- busybox `httpd` in daemon mode never listened → started with `-f` in the background from u5a-init.
- `/` returned 404: busybox 1.37 bug; with CGI enabled but BASIC_AUTH disabled, the appended `index.html` is truncated and never restored (networking/httpd.c, `urlp[0] = '\0'` vs the `#if ENABLE_FEATURE_HTTPD_BASIC_AUTH` restore). Fix: `CONFIG_FEATURE_HTTPD_BASIC_AUTH=y` (no httpd.conf, so no password).
- `head -c` / `tail -c` missing (FEATURE_FANCY_HEAD/TAIL off): the save CGI read an empty body and rejected every name; the OTA CGI and the log snapshots were broken too. Enabled both.
- `od -An` not available (od without DESKTOP) → OTA header parsed with `hexdump -e`.
- OTA kept bundle + payload copy (2 × 14 MB) in a 15 MB tmpfs → header read with `dd bs=1 count=80`, payload streamed straight to its own file; tmpfs freed on every failure. `flashcp -v` wrote 300 KB of progress into /run; `-v` dropped (flashcp verifies anyway).

Results (bench, over usb0 10.77.0.1):

- PASS `/` and `/index.html` 200; status JSON shows version, paired phones, settings.
- PASS save validation (short password rejected), save with apostrophe in the name, preferred phone → /persist/catplay_last_connect.txt.
- PASS apply: SSID "the owner Test", channel 44 → hostapd.conf and catplay.conf re-rendered, hostapd and catplay_c2a restarted without reboot; settings restored afterwards.
- PASS OTA: damaged bundle rejected ("checksum mismatch"), nothing written; good bundle written to mtd1 (u5a-system) in 1 min 46 s, verified, and the sha256 of the first 14049280 bytes of /dev/mtd1 equals the bundle payload hash. A second OTA to build 002413 followed by a reset booted the new version with settings and pairings kept.

Open: car image install and in-car test (logo, SSID, phone web page over Wi-Fi at http://192.168.50.2/, preferred phone).

## E33 — P5: first Sportage test (car image) and follow-ups

Status: **PASS on the fourth car run (2026-10-06, ~17:40): wireless CarPlay works in the Sportage** with catplay patch 0002 (photos docs/img/e33-run4-*.jpg: the CatPlay "Waiting for connection..." screen on the head unit, then "Apple CarPlay is connected"; user: "connected and working normally"). Open: the user had to tap the touchscreen once for the handshake to complete. Earlier runs: three car runs (~16:05, ~16:38, ~17:12), same result. **Correction (user, 17:31): the head unit never showed CarPlay; it shows its "Reading USB" status for about 2 s and then nothing.** No Bluetooth on the iPhone; box Wi-Fi visible. Second run fully logged (below). Third run (~17:12) logged with catplay debug output: iAP2 identification and the head unit's MFi authentication succeed; the head unit then never invites. Fix candidate built (catplay patch 0002).

First run (user report + /persist logs fetched over the box Wi-Fi, see below):

- catplay-2.log (boot #2, the car): within 1.23 s catplay went ReceivedRoleSwitch → DetectedAccessory → WaitingForIAp2Session → ConfiguringNcm → CarPlaySession on usb0 (ipv6_ll fe80::1234:5678:9abc:def0, TCP 60000, Bonjour _carplay-ctrl/_device-info) → WaitingForInvite, and logged nothing more. No dmesg from that boot was kept.
- The same catplay sequence also appears for boots on the Mac (catplay-3.log), where the kernel shows no host-role switch, so catplay's state names alone do not show what the head unit did. Bluetooth discoverability is only set by the pairing overlay after a CarPlay session with the car, so "no Bluetooth on the iPhone" follows from the drop.
- **The pad short no longer enters FEL** (three tries after the car run, the car image booted each time; it had worked all day while the factory U-Boot was on NOR). Working hypothesis: the pads are read by the factory U-Boot (its efex path), not by the BootROM; BASELINE.md's "BootROM FEL does not depend on NOR contents" is therefore not established. Recovery now relies on software FEL: from the bench image (ACM), from the car image over the box Wi-Fi (scripts/car-recover-over-wifi.sh: the Mac joins U5A-CatPlay, fetches /persist and /run logs over SSH, sends the box to FEL, installs the bench image keeping /persist, rejoins the home Wi-Fi; PASS 16:24–16:27), and the loader's own FEL-on-failure.

Second car run (boot #9, snap-4.log at 66 s; logs fetched over the box Wi-Fi 16:41):

- Head unit: **telechips wp_daudioplus** (Kia/Hyundai D-Audio), USB 05ac:0000, serial 000023062314xxxxxxxx.
- 6.52 s: Apple vendor requests on ep0: 0xc0/0x53 capabilities (4 bytes), then 0x40/0x51 wValue 1 = **role switch**; g_iphone switches the role switch to host, EHCI/OHCI start on PHY0 (the E26 path, now with a real head unit).
- 7.19 s: the head unit enumerates as a USB device on our host: iAP2 interface (class ff/f0, bulk 0x81/0x01) bound by iap2_char as /dev/iap2-0; CDC-NCM interface bound by cdc_ncm as usb0 ("Generic Apple CarPlay Headunit", patch 0012); g_iphone "role-switch accessory probe succeeded for if=usb0", status accessory. NCM speed-change notifications follow; nothing else in dmesg up to 66 s: **no USB disconnect**, role still host at 66 s.
- catplay (same timing as before): iAP2 session up at 1.2 s, NCM configured, CarPlaySession on usb0 with fe80::1234:5678:9abc:def0, _carplay-ctrl/_device-info advertised, TCP 60000 listening, then WaitingForInvite for the rest of the boot. RUST_LOG=debug had no effect: catplay_c2a's Cargo.toml selects `log` feature release_max_level_info.
- So USB, role switch, iAP2 transport and NCM all work with the real head unit. The head unit drops CarPlay at the protocol level and never sends the invite (an HTTP request to the _carplay-ctrl server, carrying its AirPlay Bonjour entry; catplay_carplay_tx_gadget/src/client.rs). The usb0 counters were missing: busybox `ip -s link` is not supported.

Third car run (boot #14, snap-4.log; catplay with debug logs):

- iAP2 link negotiated at 1.21 s; catplay sends StartIdentification; the head unit identifies as **name "Sportage", model "NQ5", manufacturer "HYUNDAI MOBIS"**, firmware V010.003.230526, hardware HW V3.0, BT 00:92:A5:xx:xx:xx, USB host transport with CarPlay interface 1 (transport_supports_car_play: Yes), languages en/ko.
- messages_sent_by_accessory: AE00 AE02 AE03 FFFB 5000 5002 4154 4156 (power, location, now playing, call state); **messages_received_from_device: AE01 FFFA FFFC FFF0 5001 4E09 4E0A 4E0B 4E0C 4E0E 4155**.
- catplay: IdentificationAccepted, RequestAuthenticationCertificate; the head unit's certificate (Apple iPod Accessories CA) and challenge response arrive; **"Authentication accepted!"**; catplay sends AuthenticationSucceeded, DeviceUUIDUpdate, DeviceInformationUpdate ("iPhone SIM"), Start/StopLocationInformation; the head unit sends StartPowerUpdates and PowerSourceUpdate (1000 mA). After 1.9 s no more iAP2 traffic from the head unit, and no invite on _carplay-ctrl (catplay re-announces every second up to 31 s+).
- Of the messages the head unit wants to receive, catplay never sends DeviceLanguageUpdate (4E0A), DeviceTimeUpdate (4E0B) or **DeviceTransportIdentifierNotification (4E0E)**; the latter is present but commented out in catplay_carplay_tx_gadget/src/carplay_client_session.rs. Our _carplay-ctrl TXT `id` is the placeholder aa:bb:cc:dd:ee:ff, which the iAP2 side never announces, so the head unit cannot tie the advertised CarPlay-control service to the authenticated iAP2 device.
- Upstream bug: IdentificationInformation::unpack_ids (core/catplay_csm/src/msg/ident.rs) loops `while i + 1 < out.len()` on an empty Vec and never advances i, so it always returns an empty list ("Modern CarPlay: false" for every car). This car indeed does not list CarPlayStartSession.
- The usb0 captures (usb0-1-boot2.pcap, usb0-1-boot4.pcap) were saved, but the text transfer over SSH mangled them; next time copy them with scp.

Fix candidate (yocto/meta-u5a/recipes-apps/catplay/files/0002-…patch): decode messages_received_from_device locally; after authentication send DeviceLanguageUpdate("en") and DeviceTransportIdentifierNotification(bluetooth "aa:bb:cc:dd:ee:ff" = the ctrl TXT id, usb "00008130000E044E384B1D3ADDDDDDDDDDDDDCAD" = g_iphone's serial) only when the head unit lists them. DeviceTimeUpdate deliberately not sent (no RTC; the head unit might take the time).

Third run preparation: catplay rebuilt with release_max_level_debug (yocto/meta-u5a/recipes-apps/catplay/files/0001-c2a-log-debug-in-release.patch); tcpdump added; u5a-init captures usb0 (up to 3 × 3000 packets, 256-byte snap) into /tmp and copies the first 192 KiB of each capture to /persist/log with every snapshot; link counters from /sys/class/net/*/statistics. Also: three boots shorter than 20 s in a row send the box to FEL (escape hatch without pads), and car-recover-over-wifi.sh forgets the box network and retries the home Wi-Fi for up to 2 min (the 16:44 run failed to rejoin automatically; the user switched back by hand).

E33a (bench, Mac as USB host, car image): Mac enumerates 05ac:12a8 but creates no network interface for it (macOS only starts iPhone USB networking for a paired iPhone), so the NCM/IPv6 CarPlay-control path cannot be tested with the Mac; dns-sd finds nothing. That path needs the head unit.

For the second car run the image (u5a-init) now writes /persist/log/snap-N.log at 3, 6, 10, 15, 20, 30, 45 and 60 s after catplay starts and every minute after: USB role and UDC state, usb0/wlan0 link counters, IPv6 addresses, processes, the last 150 kernel lines (no RTW), and the last 48 KiB of catplay (now started with RUST_LOG=debug).

## E32 — P5: persistent /persist and bench/car modes (NOR, bench mode run)

Status: **bench mode PASS 2026-10-06 15:53–15:56; car image installed 15:59** (the Mac, as host, saw the g_iphone device 05ac:12a8 36 s after the reset). Car test in the Sportage pending. Script: `sh scripts/nor-install.sh artifacts/stage1/nor-p5/<bench|car> --from-linux` (software FEL from the running bench image; dump first, Boot0 sector untouched, full readback).

What changed from E31:

- Kernel 7.2.7-v851s-p5 (scripts/build-kernel-p5.sh, modules rebuilt by build-modules-p5.sh): + SPI_SUN6I, MTD, MTD_SPI_NOR (4K sectors), MTD_OF_PARTS, JFFS2; MTD_PARTITIONED_MASTER and MTD_BLOCK off; **MTD_SPI_NOR_SWP_KEEP** (the kernel never writes the flash status/protection register). The XTX part (0x0b4018) is driven as generic SFDP.
- DT (artifacts/stage1/catplay-e28/board-p5.dts): spi0 enabled with the PC0–PC5 function 4 group (the dtsi group is /omit-if-no-ref/, so it is added explicitly), flash@0 jedec,spi-nor 50 MHz, fixed partitions **u5a-boot 0x0–0xf00000 read-only** and **persist 0xf00000–0x1000000**. bootargs gain `u5a.mode=bench|car`; the bench and car NOR images differ only in the DTB and the boot table (103 bytes).
- u5a-init: mode from the cmdline; car mode disarms the loader's safety watchdog at once, skips the debug gadget, loads iap2_char, iap2_scan and g_iphone (udc_name=musb-hdrc.2.auto device_name=default role_switch_name=4100000.usb) and uses catplay-car.conf (gadget on, udc_car musb-hdrc.2.auto), and starts dropbear on 192.168.50.2 (box Wi-Fi). Both modes: JFFS2 on mtd:persist at /persist (tmpfs fallback), /var/lib/bluetooth bind-mounted from /persist/bluetooth, /persist/bootcount, boot log and the last 64 KiB of the catplay log copied to /persist/log/*-N.log (N = boot count mod 5) 30 s after catplay starts and then every 60 s. Wi-Fi network for the iPhone: U5A-CatPlay / u5acarplay (hostapd and catplay agree).

Bench run:

- Install: dump artifacts/recovery/nor-pre-install-20261006-155017.bin, write 87 s, **16 MiB readback identical**, boot from NOR after reset.
- /proc/mtd: mtd0 u5a-boot 0xf00000 flags 0x800 (**not writeable**), mtd1 persist 0x100000 flags 0xc00 (writeable), erasesize 4 KiB. sun6i-spi has no DMA channel and runs PIO (fine for /persist).
- /persist mounted as jffs2 (64/1024 kB), boot #1; catplay stored its HomeKit identity there (homekit_rx_db.bin, homekit_tx_db.bin).
- Persistence: test file written, warm reset: boot #2, test file and both HomeKit files (md5 unchanged) survived. Logs boot-2.log and catplay-2.log written at 54 s uptime.
- Bluetooth missing on these warm boots, as in E31 (cold boots are fine).
- Car image installed the same way at 15:56–15:59 (that install still rewrote /persist; nor-install.sh now keeps 0xf00000–end unless --wipe-persist). After the reset the Mac enumerated the box as Apple 05ac:12a8 (g_iphone, catplay car-side gadget on) within 36 s. No debug channel in car mode from the Mac (the Mac's Wi-Fi is its uplink); results come from /persist/log after switching back to bench (pad short + bench install).
- Car test plan (E33): cold start in the Sportage with the box in the CarPlay USB port (pass = the head unit leaves "Reading USB" for CarPlay or a pairing prompt); expected: CatPlay pairing overlay with a PIN on the head unit, iPhone pairs with U5A-CatPlay over Bluetooth (do not join the Wi-Fi by hand), wireless CarPlay starts.

## E31 — P5: first NOR install, bench image (persistent write)

Status: **PASS 2026-10-06**: NOR install verified and the box boots CatPlay from NOR on its own; Bluetooth OK on cold power-up (missing only after warm resets, open item). Authorised by the user for all P5 NOR writes (2026-10-06: "it has to be done anyway"). Script: `sh scripts/stage1-nor-install-e31.sh` (board in FEL). Recovery: `sh scripts/nor-restore.sh` (default source: the dump this run takes first).

Result (15:30–15:33, board in FEL from E30, no user action):

- Dump artifacts/recovery/nor-pre-e31-20261006-153000.bin (sha256 72f8ba9f…, identical to nor-pre-e19): Boot0+TOC1, boot, recovery, rootfs, private, logo equal the factory backup; env, customer, UDISK differ (factory runtime data). This dump is the default restore source.
- Image built on that dump: 0x0–0x10000 unchanged. Write of 0x10000–end (16711680 bytes): 90 s. **Full 16 MiB readback byte-identical.**
- GPR[2] = 0, `xfel reset`: **the box booted from NOR on its own; bench gadget U5A-720-CATPLAY-E28 13 s after the reset**, no upload. Loader report (SRAM 0x3a000): U5AB, stage 6, JEDEC 0x0b4018, CRC32 of zImage/DTB/root = table values (0x7fef70ae, 0x9ffbe85f, 0xa740e45a), loader time 0x108c4744 ticks = 11.6 s (read + CRC). u5a-init cleared GPR[2]; watchdog disarmed (MODE 0); hostapd up; catplay running; 31 MB available. Uptime sampled for 3 min: stable, no resets.
- One kernel WARNING at 4.0 s: `netdevice: wlan0: Incorrect netdev->dev_addr` from the vendor 8733bs driver when wlan0 is brought up (dev_addr_check). Harmless here (AP works), and probably present in E28 too: the E28 "no WARN" line was not actually checked (that report command used `head -20`, which this busybox rejects).
- **Bluetooth: hci0 missing.** serial0-0 is bound to hci_uart_h5 and hci_uart loaded, but H5 never completes its sync, so hci0 is never registered (H5 sets HCI_UART_INIT_PENDING and retries silently). Checked live: PE10–PE13 function 6 (uart2), PE8 output high, RTC LOSC_CTRL 0x4010 and fanout0 31250 Hz to the radio as in the FEL boots. Reloading hci_uart, pulsing PE8 (with 8733bs removed) and pulsing PD20 (factory bt_rst_n, was disabled) did not help. Since the 14:55 pad short the board has only had warm resets; the controller may still be in the post-firmware state of an earlier boot. Next: cold power cycle from NOR.
- **Cold power cycle (user unplug/replug, 15:43): Bluetooth OK.** Box booted from NOR alone; hci0 at 3.8 s (`RTL: examining hci_ver=08 ... lmp_subver=8723`, rtl8723fs fw + config 41 bytes loaded), bluetoothd "hci0 present" at 4.49 s, hostapd and catplay up, 31 MB available. So the missing hci0 was a warm-reset effect: after a watchdog reset the BT core keeps its post-firmware state (neither PE8 nor PD20 pulses from Linux recovered it), and H5 sync at the initial rate never completes. In the car every start is a cold power-up. Open item: make BT survive warm resets (software reboot, watchdog), e.g. by finding the controller's real reset/power control or by trying H5 sync at the post-firmware baud rate.

What gets written (scripts/build-nor-image.py, artifacts/stage1/nor-e31/):

- 0x0–0x10000 not written (stock Boot0); the image builder copies it from the fresh dump and checks Boot0's eGON sum.
- TOC1 at 0x10000: factory header and item table unchanged, item 'u-boot' (0x400, 0x3c000) = u5a-loader boot build (loader/boot.c, 2.7 KiB of code behind the factory U-Boot head, padded to the factory length 0x3c000, head checksum recomputed), item 'dtb' byte-identical, add_sum recomputed (0xc9d22507 on nor-pre-e19).
- zImage 0x80000 (E28 kernel, no SPI/MTD driver), DTB 0x460000 (E28 DT; no reserved-memory node), boot table 'U5AB' 0x470000 (offset, length, DRAM address, CRC32 per image, table CRC32), rootfs.erofs 0x480000 (E28 root + u5a-init clears GPR[2] first), 0xf00000–end erased (persist, unused yet).

u5a-loader boot path: GPR[2] = FEL flag and fed 16 s watchdog at entry; SPI0 CCU reset + init; JEDEC; table checks (magic, version, count, CRC32, every image inside DRAM, never over the loader, DTB at 0x43000000, NOR offsets ≥ 0x80000); load and CRC32 each image; any failure → stage 0xE0+code in the SRAM report, watchdog SRST → Boot0 sees the flag → FEL. Success → launch.bin hand-over (USB reset, 16 s safety watchdog), r2 = 0x43000000, jump to the zImage.

Offline: loader/emu_boot.py runs the loader exactly as Boot0 would place it (TOC1 item at 0x42000000) against the whole image: clean run must reach 0x41800000 with all three images byte-exact in DRAM; a flipped byte in each image and a broken table must each end in SRST with GPR[2] set and stages 0xF0/0xF1/0xF2/0xE2. xfel `spinor write` erases the target range (aligned to the erase size; 0x10000 is aligned, so Boot0's sector is not touched) before programming.

Steps: healthy FEL; full 16 MiB dump (artifacts/recovery/nor-pre-e31-*.bin), Boot0+TOC1 must equal the factory backup; image built on that dump; `xfel spinor write 0x10000`; full readback must equal the image byte for byte; GPR[2] cleared; `xfel reset`; wait for the bench gadget without any upload.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| W− | readback differs | write problem; rewrite or restore |
| K+ | U5A-720-CATPLAY-E28 gadget after the reset, GPR[2] = 0 in Linux, SRAM boot report stage 6 | **the box boots CatPlay from NOR on its own** |
| F | proper FEL after the reset | the loader ran and rejected an image or table; SRAM report says which |
| H | half-dead FEL | Boot0 did not accept/run our TOC1 item from NOR; pad short + nor-restore.sh |
| N | nothing | pad short + nor-restore.sh |

## E30 — P5 step 2: stock Boot0 → u5a-loader (FEL, RAM only, NOR read-only)

Status: **PASS 2026-10-06 15:02** (third run). First run 14:35 half-dead FEL; second run 14:57 (E30b instrumentation) located the hang in the loader's SPI init. Script: `U5A_APPROVED=1 sh scripts/stage1-boot0-loader-e30.sh`. Package: artifacts/stage1/boot0-loader-e30/. Part (b) of the design's E30 (software FEL) already passed in E29c/E29d.

Method: the E07 technique. The patched Boot0 (artifacts/stage1/boot0-trampoline-uboot-v1/boot0.bin) differs from stock only in its checksum, a NOPed print at 0x26a42 and the literal at 0x26ad4, so its final jump helper (0x20fb8, after the MMU/cache-off routine 0x20f7a) goes to 0x30100 instead of the factory U-Boot at 0x42000000. Boot0 is staged at 0x43f00000 (loader/e30/relocate.S, rebuilt from the E07 source, which rebuilds byte-identical; only the source address changed because the DTB sits at 0x43000000), copied to SRAM 0x20000 and run. Our trampoline (loader/e30/trampoline.S) replaces the factory U-Boot that Boot0 just loaded with u5a-loader (staged at 0x43e00000) and enters it. GPR[2] is cleared first, because Boot0 itself goes to FEL when it is 0x5aa5a55a.

Boot0 facts read while preparing (disassembly): MMU on with I-cache, **D-cache never enabled** (0x20eee clears C), so no dirty-line hazard at the hand-over; 0x20f7a turns MMU and caches off before the jump. FEL decision 0x22f14: GPR[2] = 0x5aa5a55a "eraly jump fel"; 0x5aa55aa5 → crashdump handshake (writes 0x5aa55aa6, waits for 0x5aa55aa7) → FEL. Boot0 references DRAM 0x42e00000 near its TOC1 code (probably its read buffer), nothing at 0x43e00000/0x43f00000.

First attempt (14:35): all payloads verified, GPR[2] read back 0, relocator executed. Then no gadget, no factory boot, and no usable FEL for 10 minutes: the Mac showed 1f3a:efe8 while `xfel version` hung, i.e. the documented half-dead FEL (VENDOR-BOOT-RE.md §2). The runner also hung inside `xfel version` (no timeout). Not distinguishable from the data: Boot0 taking one of its error paths (it has many: spinor init, toc1 magic, DRAM init, ...) versus an exception in the trampoline or loader, which with the MMU off vectors into the BootROM and gives exactly this state. A candidate for the latter is the loader's CNTFRQ write, which is Secure-PL1 only.

Results:

- 14:55: the first pad short did not take (factory "iPhone" enumerated); nothing ran. Second pad short gave a clean FEL.
- **E30b (14:57), fresh pad FEL:** Boot0 ran, reached the trampoline (SRAM breadcrumb TRMP), the trampoline entered the loader (report magic, wdog_mode_at_entry 0xb1 from the trampoline, gpr2_at_entry 0x5aa5a55a, entry SCTLR 0x00c50878 = MMU, D- and I-cache off, CPSR SVC). The loader stopped at **stage 1, in spi_init or the JEDEC read**; 16 s later the watchdog reset into a proper FEL and the report was read back. Boot0 leaves SPI0 configured for its own DMA reads; under FEL the controller is at reset state, which is why E29 did not see this. The 14:35 half-dead FEL fits the same hang without a watchdog (the loader then turned it off).
- Fix: spi_init first asserts the SPI0 CCU reset with bus gate and module clock off, then runs the xfel sequence, and writes FCR outright (FIFO resets, no DMA requests). Stage 0x11 added after spi_init.
- **E30 (15:02) PASS:** Boot0 (RAM) → trampoline → u5a-loader → E28 kernel at 0x41800000: kernel gadget 6 s after the relocator exec. Report: JEDEC 0x0b4018, Boot0/TOC1 sums and CRC32 equal the backups, 2.02 MiB/s, stage 6 DONE. Software FEL from Linux PASS (2 s).

What E30 does not cover: Boot0 accepting our own TOC1 package and loader head from NOR (only E31 can show that; recovery is the pad short).

E30b changes (all also wanted for production):

- Trampoline: first sets GPR[2] = 0x5aa5a55a and arms the 16 s system-reset watchdog, leaves 'TRMP' at SRAM 0x3a0f0, then copies and jumps. If it runs, any later hang or exception becomes a reset into a proper FEL; a half-dead FEL that persists means Boot0 never reached it.
- u5a-loader: arms the 16 s watchdog at entry and feeds it every 64 KiB of SPI read and CRC (instead of turning it off), writes CNTFRQ only if it is not already 24 MHz, and the return-to-FEL probe turns the watchdog off before returning. Unicorn: both modes EMU_PASS.
- Runner: every `xfel version` has a 6 s timeout; outcomes K (kernel), F (proper FEL, read the breadcrumb and report), H (half-dead FEL for 30 s), X (factory boot), N (nothing).

## E29 — P5 step 1: u5a-loader probe from xfel DDR state (FEL, RAM only, NOR read-only)

Status: **PASS 2026-10-06 14:29 (E29d)** after two fixes found by E29b/E29c; E29 itself (13:57) was outcome A. Script: `U5A_APPROVED=1 sh scripts/stage1-loader-e29.sh` (`... report` re-reads the report on the running board). Package: artifacts/stage1/loader-e29/ (SHA256SUMS, expected.json). Design: docs/P5-NOR-DESIGN.md.

Why it matters: first run of our own code that reads the SPI NOR. It must read the factory flash correctly and hand over to Linux exactly as launch.bin does, before Boot0 (E30) and before any NOR write (E31).

What is new:

- loader/ (start.S, main.c, spi.c, mkimage.py; Homebrew arm-none-eabi-gcc): 1824 bytes of code behind a copy of the factory U-Boot head (branch to 0x640, `uboot` magic, stamp checksum recomputed, run address 0x42000000), 16 KiB image. Entry: the launch.bin cache/MMU cleanup, then I-cache on. SPI0 is set up with xfel's V851 sequence (MIT), commands 0x9f and 0x03 only.
- Probe mode: watchdog off; JEDEC ID; read Boot0 (0x0, 0x9000) and check its eGON stamp sum; read the TOC1 header and package (0x10000, valid_len) and check add_sum; read 4 MiB at 0x480000 with timing, CRC32 with timing; report (21 words) at 0x43f00000; then the E26 launch.bin hand-over: FEL MUSB session dropped, USB in reset, 16 s safety watchdog armed (CFG 0x16aa0001, CTRL 0x14af, MODE 0x16aa00b1; u5a-init disarms it once the debug gadget is configured), r0 = 0, r1 = ~0, r2 = 0x43000000, jump to 0x41800000.
- The kernel and root are E28's; the zImage moves from 0x42000000 to 0x41800000 (the loader occupies 0x42000000). DT: E28 + reserved-memory no-map page at 0x43f00000 for the report. CONFIG_STRICT_DEVMEM is off, so devmem reads it.
- Expected values (expected.json) come from the backups; Boot0, TOC1 and 0x480000–0x880000 are identical in full-flash-16MiB.bin and nor-pre-e19: Boot0 sum 0x8292dfc4, TOC1 add_sum 0x40d51847, CRC32 0xb0d62309.
- Offline: loader/emu_test.py runs the real image under Unicorn (Cortex-A7) with SPI0 emulated from the register usage and backed by nor-pre-e19. EMU_PASS: all checks equal expected.json, 71751 SPI bursts all with CS active and at most 64 bytes, hand-over registers r0/r1/r2 and the watchdog registers equal launch.bin's. Unicorn refuses the secure-only CNTFRQ write that launch.bin also does; the test skips that one instruction.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| A | no U5A-720-CATPLAY-E28 gadget within 90 s | loader hang (SPI wait loop) or kernel failure from 0x41800000; the 16 s watchdog only runs after the loader's reads, so a loader hang needs a power-cycle. Next: split the probe (no kernel jump) |
| L+ | report magic U5AL, stage 6, DONE | loader ran to the hand-over |
| N+ | boot0/TOC1/CRC32 equal expected.json | our SPI read of the NOR is correct |
| N− | any mismatch | SPI timing or protocol; compare JEDEC with `xfel spinor` |
| K+ | E28 system up as before | 0x41800000 hand-over works |
| T | MiB/s, projected time for 13.2 MiB | boot-time budget for E31 |
| W | wdog_mode_at_entry, gpr2_at_entry | state left by FEL; for E30 comparison |

## E28 — CatPlay P3: first catplay_c2a run on the board (FEL, RAM only)

Status: RUN 2026-10-06 13:30, **R+ B+ W+ C+**, M = 30 MB available; P not reachable on the bench by design (below). Log artifacts/logs/e28-boot-20261006-133046.log. Script: `U5A_APPROVED=1 sh scripts/stage1-catplay-e28.sh` (then `sh scripts/stage1-catplay-e28.sh check` on the same boot). Package: artifacts/stage1/catplay-e28/ (SHA256SUMS; modules/ has the 7 out-of-tree and in-tree modules).

Result:

- **R+:** `initrd_blk: registered /dev/initrd size=9592 KB`, `RAMDISK: performing direct /dev/initrd mount`, `erofs (device initrd): mounted`, `VFS: Mounted root (erofs filesystem) readonly on device 420:0`. Overlays on /etc and /var and tmpfs /persist up. u5a-init reached "ready" 4.5 s after start; the ACM gadget appeared on the Mac within the 90 s window.
- **B+:** btrtl/hci_uart loaded, hci0 present, bluetoothd 5.86 running (one harmless line: `Failed to set default system config for hci0`).
- **W+:** 8733bs (e28 build) with chplan 0x2B "CA"; hostapd `state=ENABLED freq=5180 ssid[0]=U5A-E28`.
- **C+:** catplay_c2a running (pid 110): `Starting MFI server on 0.0.0.0:9000`, HomeKit identity initialised, `Gadget manager is disabled`, `Started`. No MFi error, so bus 3 / 0x11 is accepted.
- **M:** 47088 kB total (the 9.4 MB initrd stays reserved), 30236 kB available with all services and catplay up; catplay VSZ 14.5 MB.
- No WARN/Oops/BUG/segfault/OOM in dmesg.
- Report-script bugs (busybox has no `ps -o` or `head -40`) fixed after the run.

Finding, from the source and a live test on the same boot (no FEL):

- Everything iPhone-facing (Bluetooth identity, Wi-Fi credentials, the CarPlay receiver) lives in `ProdGadget` (c2a/catplay_c2a/src/prod_gadget.rs), which only exists with `[gadget] enabled = true`. With the gadget disabled, catplay does nothing toward the iPhone.
- Live: catplay restarted with `enabled = true` and `udc_car = "no-such-udc"` (keeps the debug gadget). The wireless side came up (BlueZ alias `U5A-CatPlay`, class 0x000420, iAP2 UUID 00000000-deca-fade-deca-deafdecacaff registered); the car side loops on `FailedToSetupUsbClient(MissingUdc)` once a second, as expected.
- Discoverable/pairable and the PIN agent are only set in proxy_rpc/overlay_default.rs, the pairing overlay drawn on the head unit's screen after the wired session with the car is up; without a car, `CarPlayRxSession::reject()` refuses iPhone sessions. So upstream's flow is car first (box as wired iPhone), then the PIN on the car screen, then the iPhone pairs and moves to Wi-Fi. P cannot pass on a bench without a head unit. Discoverable was set by hand (`bluetoothctl discoverable on`) only to check that the CatPlay identity is visible.


Why it matters: first run of the CatPlay userspace on the U5A, with upstream's V821 boot model (EROFS root in RAM) on our 64 MiB board. Scope is the iPhone side only: the car-side gadget is disabled in catplay.conf (`[gadget] enabled = false`) so the ACM/NCM debug gadget keeps the single USB port. g_iphone and the role swap stay for P4.

What is new:

- Kernel 7.2.7-v851s-e28 (scripts/build-kernel-e28.sh): the E26 config plus IPV6 (no SIT), OVERLAY_FS, AF_UNIX_OOB, INOTIFY_USER, BLK_DEV_RAM, EROFS_FS + ZIP (lz4 only), and kernel/patches-7.2.7/0013 from upstream meta-sunxi: `root=/dev/initrd` registers the initrd memory as block device /dev/initrd (initrd_blk) and EROFS mounts it in place, with no copy. SPI and MTD stay off (the script refuses otherwise). zImage 3742808 bytes.
- Modules rebuilt for that kernel (scripts/build-modules-e28.sh, vermagic checked): crc-ccitt, btrtl, hci_uart, 8733bs (with patch 0001 from E27), iap2_char, iap2_scan, g_iphone.
- Root: Yocto u5a-e28-image (yocto/meta-u5a), EROFS lz4hc 9822208 bytes (2398 pages, page aligned as initrd_blk requires). Upstream C2A packages (busybox + devmem, dbus, bluez5, hostapd, dropbear, catplay) plus u5a-bench: /sbin/u5a-init, /etc/u5a/{catplay.conf, hostapd.conf, udhcpd-*.conf, bluetooth-main.conf}, the modules, and the E25 rtl8723fs firmware. catplay_c2a is not UPX-packed, so it pages from the compressed image.
- Load layout: zImage 0x42000000, DTB 0x43000000 (E26 DT, only /chosen changed), rootfs.erofs 0x43400000–0x43d5e000 (E26's 0x43800000 would run past the end of DRAM at 0x44000000), launch.bin 0x28000 unchanged (r2=0x43000000, jump 0x42000000). bootargs `root=/dev/initrd rootfstype=erofs ro init=/sbin/u5a-init console=ttyGS0,115200 ... loglevel=5` (no ignore_loglevel, so the RTW debug flood stays out of the ACM shell).
- /sbin/u5a-init, in upstream boot_early() order: proc/sys/dev/run/tmp, tmpfs overlays on /etc and /var, tmpfs /persist; debug gadget serial U5A-720-CATPLAY-E28 (ACM shell on ttyGS0, usb0 10.77.0.1, dropbear with an empty root password); lo + V821 sysctls; dbus; insmod BT modules and 8733bs rtw_country_code=CA; wlan0 192.168.50.2/24 + fe80::1234:5678:9abc:def4; hostapd (SSID U5A-E28, WPA2-PSK `u5atest28`, ch36); udhcpd; bluetoothd -f /etc/u5a/bluetooth-main.conf (FastConnectable, JustWorksRepairing=always); catplay_c2a. Logs in /run/u5a/.
- catplay.conf: MFi bus 3 addr 0x11 (E25), hci0, wlan0, network U5A-E28/u5atest28 ch36, BT name U5A-CatPlay, gadget disabled.
- Offline checks: `sh -n` on u5a-init; every command it calls exists in the image; under qemu-arm with the extracted root, catplay_c2a starts, reads /etc/catplay/catplay.conf and stops at `open("/dev/i2c-3")` (no I2C in qemu), so libraries, config path and parsing are fine.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| A | no U5A-720-CATPLAY-E28 gadget within 90 s | kernel, initrd_blk/EROFS root or u5a-init failed before the gadget; no console before the gadget, so next run adds a fallback |
| R+ | `/dev/initrd` mounted as erofs on /, initrd_blk line in dmesg | in-place EROFS root works on this board |
| B+ / B− | hci0 present and bluetoothd running / not | BT stack in the Yocto userspace |
| W+ / W− | hostapd `state=ENABLED freq=5180 ssid=U5A-E28` / not | AP under the new image (driver rebuilt for e28) |
| C+ | catplay_c2a still running after 40 s, log past MFi start | catplay runs on V851S; MFi chip accepted |
| C− mfi | catplay exited with an MFi error | i2c bus/address or CP 2.0C handling; log |
| C− other | catplay exited or crashed otherwise | log + dmesg (segfault, OOM) |
| M | MemAvailable after boot | headroom with catplay running (E26 baseline about 35 MB) |
| P+ | an iPhone shows the box (Bluetooth list or Settings → General → CarPlay) | wireless CarPlay discovery works; pairing is the next step |

## E27 — CatPlay P2: iPhone-facing Wi-Fi AP and Bluetooth radio check (live, no FEL)

Status: **S+ PASS, V+ PASS (one of two phones) 2026-10-06.** Runs live on the still-running E26 boot over usb0 (RAM /tmp only). Script: `sh scripts/live-ap-bt-e27.sh start [a|g]`, then `check`, then `stop`. Package: artifacts/stage1/p2-ap-bt-e27/ (hostapd, hostapd_cli, u5a-hci; configs in userspace/ap-e27/).

Why it matters: wireless CarPlay runs over the box's Wi-Fi AP (the iPhone joins it after a Bluetooth/iAP2 hand-over). CatPlay starts hostapd on wlan0 at 192.168.50.2/24 plus fe80::1234:5678:9abc:def4, and busybox udhcpd hands out 192.168.50.100–200. For non-AIC radios its template is 5 GHz ch36 802.11n WPA2-PSK/CCMP.

What is new (offline):

- hostapd 2.12, static ARMv7, nl80211 through the static libnl from the wpa_supplicant build, internal crypto, 802.11n/ac/w, control interface. Build: `limactl shell u5a-build -- sh -s < scripts/build-hostapd-armhf.sh`. SAE (WPA3) is left out: the internal crypto has no EC math. CarPlay uses WPA2-PSK.
- userspace/bt-hci/u5a-hci.c: a static raw-HCI tool (no bluez yet; bluez + dbus come with the P3 Yocto build). It reads BD_ADDR and the local version, sets the name and Class of Device (car audio), enables inquiry + page scan, runs a classic inquiry (radio TX and RX) and a passive LE scan (RX).
- Configs: hostapd-5g.conf (ch36, country CA), hostapd-2g.conf (ch6, fallback), udhcpd.conf (CatPlay's range). Test SSID `U5A-E27`, passphrase `u5atest27` (a throwaway RAM-only test AP).
- The client is an iPhone, joined by hand. The Mac cannot be the client: its uplink is its own Wi-Fi, and macOS hides scanned SSIDs without location permission.

Live findings:

- **BT+ info and BT+ radio:** BDADDR 68:8f:c9:xx:xx:xC, LOCAL_VERSION lmp_subver=0x776b (same firmware as E25). Classic inquiry found 0 devices (no nearby discoverable BR/EDR). LE scan 5 s: 12 devices, 135 reports.
- **AP− 5G then AP+ after two driver issues, both RAM-only, no FEL:**
  1. Without `rtw_country_code=CA` the driver stays on world regd 00; every 5 GHz channel is NO_IR, so hostapd cannot pick ch36. The driver also ignores cfg80211 `set_country` (`CONFIG_RTW_IOCTL_SET_COUNTRY` is off). Fix: `insmod ... rtw_country_code=CA` (chplan 0x2B). Then `state=ENABLED freq=5180`.
  2. After AP-ENABLED, Mac CoreWLAN and iPhone 14 Pro Max saw the SSID as **WEP**, not WPA2. iPhone 14 accepted the passphrase then immediately asked for a password again. Driver log: `auth rejected due to bad alg [alg=1, auth_mib=0]` (shared-key vs open). Cause: `update_BCNTIM()` in vendor/rtl8733bs-modern/core/rtw_ap.c always skipped 3 bytes for a DS Parameter Set IE. hostapd omits that IE on 5 GHz, so the TIM insert overwrote the RSN IE in the on-air beacon. Patch: kernel/patches-rtl8733bs/0001-ap-update_BCNTIM-no-DS-IE-on-5GHz.patch. After reload, CoreWLAN reports `wpa2Personal` + PHY 11a/11n, rssi -32.
- **iPhone 17 Pro Max not seeing the SSID** was caused by the same mangled 5 GHz beacon (iOS 26 is stricter about malformed IEs). After the 0001 reload it lists U5A-E27.
- **S+ (both phones):** iPhone 14 Pro Max and iPhone 17 Pro Max joined U5A-E27 on 5180 MHz. `num_sta=2`, both `[AUTH][ASSOC][AUTHORIZED]`, `AP-STA-CONNECTED` + `EAPOL-4WAY-HS-COMPLETED` (RSN) for each, HT MCS7 65.0/72.2 Mb/s, signal -49/-59 dBm. udhcpd leases 192.168.50.100 and .101 (host name `iPhone`; private random MACs 0a:0a:bf:xx:xx:xx and 06:d2:5a:xx:xx:xx, which one is which phone was not recorded). Board→phone ping 3/3 each, 3–59 ms (LPS power save still on). iPhone 14 never associated before the fix, so no "forget network" was needed.
- **V+ (Bluetooth visibility):** the first look showed only `smartbox-2CF5` (stock-firmware style name) under Other Devices, not `U5A-E27`. The board's BDADDR 68:8f:c9:xx:xx:xC and wlan0 68:8f:c9:xx:xx:xb do not end in 2CF5. After `u5a-hci 0 name U5A-BT-775C` + `discoverable` (all status=0), `smartbox-2CF5` disappeared and iPhone 17 Pro Max listed `U5A-BT-775C`; iPhone 14 Pro Max did not. Unresolved whether `smartbox-2CF5` was a nearby stock unit that went away or a stale iOS name for this board. Board-side 10 s inquiry while the phones were on the Bluetooth page: 1 device, F0:D7:93:xx:xx:xx rssi -46 (which phone not recorded). Raw HCI only, no SDP/iAP2 records yet (bluez comes in P3), so iOS filtering is plausible.
- Host note: the first `check` reported `NO_USB_NET` only because the Mac had no ARP entry for 10.77.0.1 yet; a plain retry worked. No board reset.
- Kernel has no IPv6; CatPlay needs link-local IPv6 later. Combine with the next FEL rebuild.
- Test SSID `U5A-E27`, passphrase `u5atest27`.

Pre-declared outcomes:

| Code | Observation | Meaning / next |
| --- | --- | --- |
| BT+ info | `BDADDR` + `LOCAL_VERSION ... lmp_subver=0x8723` | controller usable from userspace |
| BT+ radio | `INQUIRY_DEVICES>0` or `LE_DEVICES>0` | RF path works (TX+RX for inquiry, RX for LE) |
| BT− radio | both 0 | antenna/RF or controller config; the AP part is still run |
| V+ | iPhone lists "U5A-E27" under Bluetooth | discoverable classic device seen by the target phone |
| AP+ | `state=ENABLED freq=5180` | 5 GHz AP mode works on 8733bs |
| AP− 5G | hostapd fails on ch36 (regulatory / no AP mode on 5 GHz) | retry `start g`; record the driver message |
| AP− all | fails on 2.4 GHz too | driver AP mode over cfg80211 broken; dmesg + hostapd -dd log |
| S+ | iPhone joins; `AP-STA-CONNECTED`, handshake completed, lease in 192.168.50.100–200, ping OK | P2 Wi-Fi done |
| S− | iPhone sees SSID but cannot join | WPA/HT parameters; hostapd log |
| S− WEP | Mac/iPhone lists the 5 GHz SSID as WEP | `update_BCNTIM` DS-IE skip bug; apply 0001 and reload |

## E21 preparation notes (historical) Script: `U5A_APPROVED=1 sh scripts/stage1-mainline-7.2.7-wifi-e21.sh`

Changes from E20, and nothing else:

1. The kernel is rebuilt with CONFIG_SUN6I_RTC_CCU=y (zImage 3e70cac0…; vermagic unchanged, so the same 8733bs.ko is used).
2. The initramfs is repacked with the missing `lib` directory added. `u5a_probe_check.py cpio-patch` now inserts missing parents automatically. The new `cpio-verify` models the kernel unpacker: it flags the wifi-v1 archive and passes the E21 archive.
3. The probe snapshot also prints `devices_deferred`, and the gadget serial is U5A-720-WIFI-E21.

Hypothesis: with pwrseq probing (PE8 high, fanout0 32 kHz from osc32k/RC) and mmc1 up, the RTL8733BS enumerates as SDIO 024c:b733/b73a. Outcomes A/B/C/D are the same as E20. B now counts as real hardware evidence only if `devices_deferred` is empty and the mmc1 host exists.

## E20 preparation notes (historical)

Script: `U5A_APPROVED=1 sh scripts/stage1-mainline-7.2.7-wifi-e20.sh` (needs one healthy FEL entry).

Chain: E01 direct launch, with the same addresses and launch.bin. zImage goes to 0x42000000, DTB to 0x43000000, initramfs to 0x43800000 and launch.bin to 0x28000; each is read back, then exec 0x28000. No Boot0 or U-Boot is involved. The kernel has no SPI/MTD driver and spi0 is disabled in the DT, so NOR cannot be touched.

Artifacts in artifacts/stage1/mainline-7.2.7-wifi-e20/ (SHA256SUMS):

- zImage: same as wifi-v1 (2ebdbe75…), built from build/linux-7.2.7-wifi-out with CFG80211, MMC_SUNXI, PWRSEQ_SIMPLE and MODULES.
- board.dtb: wifi-v1 DTB with the only change being `linux,initrd-end` set to 0x43a28f0e = 0x43800000 + 2264846. The unpatched wifi-v1 DTB had end == start, so it was never runnable.
  - Compared with the E01 DTB, the only differences are mmc1 enabled (4-bit, 50 MHz, non-removable, SDIO-only), pins PE0–PE5 (sdc1, mux 6, pull-up) and wifi-pwrseq (PE8 active-low reset/enable, FANOUT0 32 kHz from OSC32K, 200 ms).
- initramfs.cpio.gz: the wifi-v1 archive repacked with `u5a_probe_check.py cpio-patch`. Only `/init` is replaced and `/bin/u5a-wifi-probe` added; the other 420 entries are byte-identical, including /dev/console and 8733bs.ko (2b8e100f…).
  - Sources are in userspace/mainline-wifi-e20/.
  - /init does NOT insmod automatically. It brings up the ACM+NCM gadget "U5A RAM WiFi Probe" with serial U5A-720-WIFI-E20, a shell on ttyGS0, and usb0 10.77.0.1 with udhcpd and telnetd as a backup channel.
- The host tool tools/u5a_serial_session.py drives the steps over ACM and logs everything to artifacts/logs/e20-*.log. The steps are boot state, state BEFORE, insmod (30 s timeout), state AFTER, ifup wlan0 (the Realtek driver downloads firmware on open), dmesg and result.
  - The kernel console is on ttyGS0, so an oops during insmod lands in the same log.
  - Self-tested on a bridged pty pair.
- State snapshots include the mmc hosts and cards, SDIO vendor/device, PE CFG/DAT/PULL and PIO power-mode registers (read-only devmem), clk_summary, debug gpio and pinmux.

Pre-declared outcomes:

- A: no U5A-720-WIFI-E20 gadget within 60 s. The Wi-Fi kernel+DT does not boot; E01 with the same kernel config differences is the reference. Offline analysis.
- B: gadget present, no SDIO device. The problem is mmc1 power, PE IO voltage, pwrseq/32 kHz clock or the DT. Diagnose live in the same session (registers already captured); no new FEL entry is needed for that.
- C: SDIO 024c:b733 or 024c:b73a present, no wlan0. Driver or port issue; dmesg is captured. C' (device lost during insmod) means a driver crash.
- D: wlan0 present. Milestone 2 PASS; the ifup result decides whether the firmware download works.

## Closed hypotheses

Do not reopen without contradictory evidence:

- xfel DDR profile is fundamentally wrong;
- Boot0 cannot execute from RAM;
- Boot0 rewrites U-Boot executable code;
- factory environment never reaches bootm;
- Boot0 DDR retraining destroys every staged image;
- VID:PID 1f3a:efe8 always means healthy FEL.
- vendor init_boot / ramdisk semantics block a cpio ramdisk (E16);
- U-Boot FDT/initrd manipulation produces a layout Linux cannot use (E16), provided the constraints in docs/VENDOR-BOOT-RE.md §6 hold.

## Open hypotheses, ranked

Vendor 4.9 route is STOPPED (E19); the items below are kept for the record only:

1. The custom GCC6 4.9 kernel has a compatibility problem at or after the real U-Boot handoff.
2. Lower probability: a CPU/cache/secure-state issue remains at the final jump.

Plan B: closed as PASS (E22, E23).

CatPlay port: see docs/CATPLAY-PORT.md §5.
