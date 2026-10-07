# catplay-v851s

[English](README.md)

把开源的 CarPlay 实现 [CatPlay](https://github.com/catplay-labs/catplay) 移植到采用**全志 V851S** 芯片、
**Realtek RTL8733BS** 无线芯片的"有线转无线 CarPlay 盒子"上。盒子插在只支持有线 CarPlay 的车上，iPhone 通过
无线连接盒子。

在一台 **LY2734 smartBox（U5A）** 和一辆 **2024 款起亚 Sportage** 上开发并测试：无线 CarPlay 可以正常使用，
画面、声音、触屏都已测过。

这是独立的移植项目，不是 CatPlay 官方发布版。它会替换盒子原来的固件，动手前请把本页读完。

## 仓库内容

| 目录 | 内容 |
| --- | --- |
| `loader/` | u5a-loader：放在原厂 U-Boot 位置的小型启动程序，从闪存读取内核、设备树和系统（带 CRC 校验），然后启动 Linux |
| `kernel/` | Linux 7.2.7、RTL8733BS Wi-Fi 驱动、CatPlay `g_iphone` 驱动的补丁；内核配置；板级设备树（桌面版和车载版） |
| `yocto/meta-u5a/` | 基于官方 [catplay-firmware](https://github.com/catplay-labs/catplay-firmware) 的 Yocto 层：机器配置、系统镜像、启动脚本、设置网页、固件升级、CatPlay 补丁 |
| `scripts/` | 下载源码、编译内核/驱动/镜像、安装、恢复出厂、远程救援 |
| `docs/` | [硬件](docs/hardware.md)、[启动流程与闪存布局](docs/boot-and-flash.md)、[移植说明](docs/porting-notes.md)、[实验记录](docs/experiment-log.md)、[提交给原作者的内容](docs/upstream/)（英文） |
| `blobs/` | 需要从你自己的盒子里取出的文件（原厂闪存备份、蓝牙固件），不放进 Git |

## 功能

- 从盒子自己的闪存启动，启动程序到内核约 6 秒，然后运行 CatPlay。
- 手机设置网页：连上盒子的 Wi-Fi 后打开 `http://192.168.50.2/`。可以改 Wi-Fi 名称和密码、蓝牙名称、
  5 GHz 信道，设置优先连接的 iPhone。
- 同一页面上可以升级固件：写入前先校验 SHA-256；启动程序、原厂 Boot0 和你的设置都不会被改动。
- 连接画面可以换成自己的图片（`yocto/meta-u5a/recipes-apps/catplay/files/u5a-logo.jpg`）。
- 有多种不用拆机的救援方法（见 docs/boot-and-flash.md）。

默认网络：Wi-Fi `CatPlay-V851S`，密码 `catplay123`，可以在设置网页里修改。

## 当前状态

| | |
| --- | --- |
| 从闪存启动，设置和配对记录断电保存 | 正常 |
| 无线 CarPlay，2024 起亚 Sportage（现代摩比斯 D-Audio 车机） | 正常（需要 CatPlay 补丁 0002 + 0003） |
| 设置网页、Wi-Fi 升级固件 | 正常 |
| 第一次配对 | 需要在车机屏幕上点一下（确认蓝牙配对） |
| 软重启后的蓝牙 | 要断电重启才能恢复（设计上已避开软重启） |
| 手机晚到、手机 Wi-Fi 关掉再打开 | 自动重连（CatPlay 补丁 0006–0008） |
| 自动重连后的触屏 | 出现过一次失灵，之后每次都正常；还在排查 |
| 其他车型、其他 V851S 盒子 | 未测试 |

## 编译

需要：一台跑 Yocto 的 Linux 构建机（aarch64 或 x86_64 虚拟机都可以：16 GB 内存加交换空间，100 GB 硬盘）、
`arm-none-eabi-gcc`、`dtc`、Python 3、[xfel](https://github.com/xboot/xfel)。内核和启动程序是在 macOS
（Homebrew）上编译的；在 macOS 上还要装 GNU make、sed、findutils（并放在 PATH 最前面）以及 `libelf`。

1. 把你自己的文件放进 `blobs/`（见 [blobs/README.md](blobs/README.md)）。
2. 下载源码并打补丁：`sh scripts/fetch-sources.sh`
3. 内核和驱动：`sh scripts/build-kernel.sh && sh scripts/build-modules.sh`
4. 系统（在 Yocto 构建机上，本仓库要在同样的路径下可见）：
   `sh scripts/yocto-setup.sh`，然后
   `cd ~/yocto/catplay-firmware && . openembedded-core/oe-init-build-env ~/yocto/build && bitbake u5a-e28-image`
5. 打包：`sh scripts/build-images.sh <.../u5a-e28-image-v851s-rtl8733bs.rootfs.erofs-lz4hc>`，
   得到 `out/bench/`、`out/car/` 和升级文件 `out/u5a-ota-*.bin`。

## 安装

**这会替换盒子的固件，有把盒子弄坏的风险。** 请保管好你的原厂闪存备份。

1. 让盒子进入 FEL 模式（第一次：原厂固件下短接测试点，见 docs/hardware.md）。
2. `sh scripts/nor-install.sh out/bench`（或 `out/car`）。脚本会先把整块闪存备份到 `backups/`；如果闪存开头
   64 KB 和镜像不一致就拒绝继续；永远不写 Boot0；写完全部读回比对，然后重启。
3. 桌面版：盒子在电脑上显示为一个串口和一个网卡（10.77.0.1）。车载版：直接插到车上。

以后升级：用设置网页，或者在桌面版下运行 `scripts/nor-install.sh out/car --from-linux`。
恢复出厂：`scripts/nor-restore.sh`。

## 致谢

- [CatPlay](https://github.com/catplay-labs/catplay) 和 [catplay-firmware](https://github.com/catplay-labs/catplay-firmware)：
  所有 CarPlay 功能。内核补丁 0001–0013（btrtl RTL8733BS、musb / USB PHY 角色切换、cdc-ncm、直接挂载 EROFS
  系统）来自 catplay-firmware 的 meta-sunxi（V821 移植）。
- [prototype-v851s-port](https://github.com/hbouhadji/prototype-v851s-port)：主线 Linux 的 V851S/V853 芯片支持。
- [RTL8733BS_WiFi_linux_v5.14.1.1-46](https://github.com/newbie-461/RTL8733BS_WiFi_linux_v5.14.1.1-46)：Wi-Fi 驱动。
- [xfel](https://github.com/xboot/xfel)：FEL 工具；它的 V851 SPI 程序给出了 SPI0 的初始化方法。

## 授权

GPL-2.0-only，见 [LICENSE](LICENSE)，与 CatPlay 配方和 Linux 内核相同。

本项目与苹果、CatPlay、全志、Realtek 以及盒子厂商均无关联。CarPlay 和 iPhone 是苹果公司的商标。
