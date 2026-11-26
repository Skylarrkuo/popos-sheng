# 小米平板 6S Pro · Pop!_OS 26.04 COSMIC

为小米平板 6S Pro 12.4（`sheng`、SM8550、ARM64）构建 Pop!_OS 26.04 LTS。根系统取自 System76 官方 ARM64 ISO，桌面使用 COSMIC。内核与 DTB 面向 Sheng，按 **Android A 槽、Pop!_OS B 槽、独立 `linux` 根分区** 的双系统布局打包。

| 产物 | 用途 |
| --- | --- |
| `boot-popos-sheng-dual.img` | 安卓启动格式的内核和 Sheng DTB，刷入 `boot_b` |
| `rootfs-popos-26.04-cosmic-sheng-linux.img` | Android sparse ext4 根镜像，展开为 20 GiB，刷入 `linux` |
| `SHA256SUMS` | 两个可刷入文件的 SHA‑256 |
| `apt-local/` | 带签名的本地 APT 仓库，内含内核、固件、音频配置、设备平台包和 COSMIC Settings |

## 在 GitHub Actions 构建

1. 打开 [Build Pop!_OS for Sheng](https://github.com/Skylarrkuo/popos-sheng/actions/workflows/build.yml)，或在自己的 Fork 中进入同名工作流。
2. 点击 **Run workflow**，选择分支和需要的选项。工作流会校验固定来源的 SHA‑256，编译 COSMIC Settings 和 Sheng 内核，再生成刷机镜像。
3. 构建成功后到 [Releases](https://github.com/Skylarrkuo/popos-sheng/releases) 下载启动镜像、压缩根镜像、签名 APT 仓库和校验清单。每次运行生成独立的 Release。运行详情的 `sheng-popos-26.04-arm64-build` Artifact 提供构建报告。

| 输入 | 默认值 | 用途 |
| --- | --- | --- |
| `iso_url` | 留空 | 使用固定的 System76 官方 ISO。也可填写指向同一文件的 HTTPS 镜像，SHA‑256 必须与 [sources.tsv](sources.tsv) 一致 |
| `qemu_smoke_test` | `true` | 用通用 ARM64 QEMU 检查内核能进入 Pop!_OS 用户空间 |

GitHub 要求单个 Release 附件小于 2 GiB。云端用 Zstandard 压缩根镜像和 APT 仓库，达到上限的压缩包会分成每卷最多 1,900,000,000 字节的 `.part-001`、`.part-002` 等文件。下载附件和校验清单后，在 Linux 或 WSL 进入下载目录。 [GitHub Release 附件限制](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

```bash
sha256sum -c SHA256SUMS.download
rootfs=rootfs-popos-26.04-cosmic-sheng-linux.img.zst
if [ -f "$rootfs" ]; then
  zstd -d "$rootfs"
else
  LC_ALL=C cat "$rootfs".part-* | zstd -d -o "${rootfs%.zst}"
fi
sha256sum -c SHA256SUMS
```

用 `tar --zstd -xf apt-local-arm64.tar.zst` 解包本地 APT 仓库。如果 APT 压缩包也分卷，执行 `LC_ALL=C cat apt-local-arm64.tar.zst.part-* | tar --zstd -xf -`。只下载刷机文件时，可用 `sha256sum -c --ignore-missing SHA256SUMS.download` 校验下载件，再用 `SHA256SUMS` 校验解压后的完整镜像。

### 输入版本

[sources.tsv](sources.tsv) 固定了 System76 的 ISO、COSMIC Settings 源码、Sheng 7.2.6 内核、适配源码和固件的下载来源与 SHA‑256。[device-sources.tsv](device-sources.tsv) 列出设备服务包。构建期间的基础软件包由 Pop!_OS 和 Ubuntu 的签名 APT 软件源提供，实际版本记录在 `packages.tsv`。

## 本地构建

推荐原生 ARM64 Ubuntu 26.04 编译 COSMIC Settings。内核和根镜像也可在 Ubuntu 24.04 或 x86‑64 上构建，x86‑64 主机需安装 `qemu-user-static` 并使用提前编译的 ARM64 COSMIC Settings 包。完整构建建议预留至少 30 GiB。

```bash
git clone https://github.com/Skylarrkuo/popos-sheng.git
cd popos-sheng

sudo apt-get update
sudo apt-get install -y bc bison build-essential clang cpio curl device-tree-compiler \
  dpkg-dev e2fsprogs file flex gnupg kmod libelf-dev libssl-dev lld llvm lz4 \
  python3 rsync squashfs-tools xz-utils zstd android-sdk-libsparse-utils
bash scripts/fetch-inputs.sh
# 在原生 ARM64 Ubuntu 26.04 中编译 COSMIC Settings。
sudo apt-get install -y debhelper devscripts just libdav1d-dev libinput-dev \
  libudev-dev libwayland-dev libxkbcommon-dev pkg-config
# 先安装 rustup，再安装源码指定的工具链。
rustup toolchain install 1.95.0 --profile minimal
bash scripts/build-cosmic-settings.sh
sudo bash scripts/build-kernel.sh
sudo bash scripts/prepare-rootfs.sh
sudo bash scripts/build-device-packages.sh
sudo bash scripts/build-image.sh
sudo bash scripts/publish-local-apt.sh
```

x86‑64 Linux 可从原生构建的 `apt-local/pool/` 获取 `cosmic-settings_*+sheng1_arm64.deb`。用 `SHENG_POP_COSMIC_DEB` 和 `SHENG_POP_COSMIC_DEB_SHA256` 提供包路径和构建记录中的 SHA‑256，执行 `scripts/build-cosmic-settings.sh` 导入，再执行后续步骤。

Windows 可用 PowerShell 7 和 WSL 2 的 `Ubuntu-24.04`。在 WSL 安装镜像构建依赖及 `qemu-user-static`，将官方 `pop-os_26.04_arm64_generic_1.iso` 放到仓库的上一级，准备同一版本的 ARM64 COSMIC Settings 包，在项目目录执行以下命令。构建日志会在当前终端显示。

```powershell
pwsh -File .\Fetch-Inputs.ps1
pwsh -File .\Build-Visible.ps1 -CosmicDeb 'C:\path\to\cosmic-settings_arm64.deb' -CosmicDebSha256 '<SHA-256>'
```

本地输出在 `out/`，两份 `.img` 可直接交给 Fastboot。Linux 构建可通过 `SHENG_POP_ISO` 指向已下载的 ISO，通过 `SHENG_POP_ISO_URL` 指定同一固定文件的下载镜像。`SHENG_POP_WORK` 用来选择临时目录，修改输入版本时请使用新的工作目录。`SHENG_POP_JOBS` 调整内核编译并发数。`SHENG_POP_QEMU_AARCH64` 可指定静态用户态模拟器的绝对路径。

### 使用本地 APT 仓库

将 `apt-local/` 整个目录复制到平板，作为本地 `file:` 软件源使用。套件写 `./`，`Signed-By` 指向这次构建的 `popos-sheng-archive.gpg`。可用 `SIGNING-KEY-FINGERPRINT.txt` 核对公钥指纹，`local-apt-policy.txt` 记录构建时 APT 选中的内核包。GitHub Actions 每次运行会在 runner 上生成该次构建的签名密钥，产物包含公钥和签名。

## 在平板上手动刷入

以下步骤适用于 **型号为 `sheng`、已解锁 Bootloader、Android 的 A 槽可用，并且已建好独立 `linux` 分区** 的设备。第一次分区可能需要清空 Android 用户数据，请先阅读上游安装教程，并准备能恢复 Android 的固件。在电脑端使用 Android SDK Platform‑Tools。 [Sheng 上游安装教程](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/blob/48c3155e6c165706f426811773316bd1055fd5e3/docs/en/installation.md) · [Android Platform‑Tools](https://developer.android.com/tools/releases/platform-tools)

刷入会清除 B 槽的设备树覆盖，并覆盖 `boot_b` 和现有 `linux` 文件系统。先核对下载的两个镜像，进入引导加载器 Fastboot，检查产品型号和分区容量。

```powershell
Get-FileHash -Algorithm SHA256 .\boot-popos-sheng-dual.img, .\rootfs-popos-26.04-cosmic-sheng-linux.img
fastboot devices
fastboot getvar product
fastboot getvar partition-size:boot_b
fastboot getvar partition-size:linux
```

将哈希与 `SHA256SUMS` 对照。确认 `product` 为 `sheng`，`boot_b` 大于或等于启动镜像的字节数，且 `linux` 至少 **20 GiB**（`0x500000000`）。逐条执行以下命令，确认当前步骤成功后再继续。

```powershell
fastboot erase dtbo_b
fastboot flash boot_b .\boot-popos-sheng-dual.img
fastboot -S 512M flash linux .\rootfs-popos-26.04-cosmic-sheng-linux.img
fastboot set_active b
fastboot getvar current-slot
fastboot reboot
```

首次启动会扩展 ext4 以使用 `linux` 分区的容量。镜像默认使用简体中文，云端产物的初始用户名和密码均为 `starin`。本地构建的初始登录信息在 `out/login.txt`。首次登录后请运行 `passwd` 修改默认密码。

在 A 槽 Android 仍可用的双系统布局下，可从引导加载器 Fastboot 执行 `fastboot set_active a`，用 `fastboot getvar current-slot` 确认 A 槽后重启回 Android。

## 适配与验证

| 范围 | 已包含的组件或已记录的真机结果 |
| --- | --- |
| 显示、图形和触控 | Sheng DTB、MSM DRM、Adreno 固件和 Mesa Freedreno。真机已启动 COSMIC Wayland，内屏运行在 3048 × 2032，Turnip 识别到 Adreno 740 |
| Wi‑Fi、蓝牙、USB | WCN7850 固件、蓝牙固件及 Qualcomm DWC3 / Type‑C 支持。真机 Wi‑Fi、蓝牙键鼠已检查 |
| 音频、摄像头 | Cirrus 扬声器固件、WCD938x 自动加载、Sheng ALSA UCM、libcamera 和 V4L2。真机验证了内置扬声器输出和摄像头枚举，摄像画质有待实测 |
| 键盘、触控笔、传感器 | Pogo DevAuth、键盘与触控笔帮助程序、FastRPC、SSC 和 iio-sensor-proxy。Pogo 认证服务已确认能启动，实体 Pogo 键盘仍待联调 |
| 电池、快充、指纹 | MiPPS 认证、充电模式工具和 FPC1553 配套包。真机已看到充电状态与成功的 MiPPS 认证，指纹录入仍待实测 |

构建会检查内核与 DTB、模块、COSMIC 会话、APT 依赖、ext4、稀疏镜像展开内容及 SHA‑256。通用 ARM64 QEMU 只覆盖内核进入用户空间和 COSMIC 会话文件检查。真机上的 COSMIC 压缩纹理导入偶有报错，摄像头、指纹、Pogo 和长期温控仍需各自场景验收。

镜像内置 COSMIC「关于」硬件信息修复，可显示设备型号、SM8550、Adreno 740、UFS 与系统分区容量、内屏分辨率和电池设计容量。镜像保留补丁版 `cosmic-settings`，避免系统更新自动覆盖这项修复。需要回到发行版自带的设置程序时，可以执行 `sudo apt-mark unhold cosmic-settings`。

COSMIC 电池菜单使用 TuneD PPD，首启默认启用平衡挡。三档保留 `schedutil` 和内核温控，性能挡允许 X3 使用 3.187 GHz 睿频上限，实际频率由负载和温控决定。内核也启用了 System76 调度服务所用的进程事件接口。

| 挡位 | 中核频率范围 | X3 上限 |
| --- | --- | --- |
| 省电 | 499.2–2188.8 MHz | 2342.4 MHz |
| 平衡 | 614.4–2803.2 MHz | 2956.8 MHz |
| 性能 | 614.4–2803.2 MHz | 3187.2 MHz |

## 致谢与第三方来源

- [code002-2/ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng) 的设备构建方案、内核配置、ALSA UCM 和 Android 启动包制作，为本项目提供了移植基础。[Xiaomi Pad 6S Pro Linux 移植](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux) 提供了安装与双系统文档。
- [map220v](https://github.com/map220v) 推进了 Sheng 的主线 Linux、设备树和 TWRP 适配。[alghiffaryfa19](https://github.com/alghiffaryfa19/Linux-xiaomi-sheng) 的构建项目和设备包为音频、输入及传感器的适配提供了基础。
- [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline)、[debian-sheng](https://github.com/ianchb/debian-sheng) 与 [sheng-firmware](https://github.com/ianchb/sheng-firmware) 提供了内核分支、设备功能包与固件来源。
- 感谢 Dylan Van Assche 和 SSC 后端贡献者维护传感器支持，感谢 System76 和 COSMIC 社区提供官方 ARM64 根系统、桌面和软件源。 [iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) · [System76 官方下载](https://system76.com/download-pop/)

Git 历史保留构建代码、配置和来源清单。ISO、固件、第三方软件包、签名私钥及刷机镜像在构建时获取或生成。各第三方组件适用其上游许可，固件归相应权利人。Linux 内核源码与配置见主线移植仓库，`mkbootimg` 源自 AOSP。 [AOSP mkbootimg](https://android.googlesource.com/platform/system/tools/mkbootimg/) · [COSMIC Settings](https://github.com/pop-os/cosmic-settings)
