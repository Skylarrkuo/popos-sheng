# 小米平板 6S Pro · Pop!_OS 26.04 COSMIC

为小米平板 6S Pro 12.4（`sheng`、SM8550、ARM64）构建 Pop!_OS 26.04 LTS。根系统取自 System76 官方 ARM64 ISO，桌面使用 COSMIC。内核与 DTB 面向 Sheng，按 **Android A 槽、Pop!_OS B 槽、独立 `linux` 根分区** 的双系统布局打包。

| 产物 | 用途 |
| --- | --- |
| `boot-popos-sheng-dual.img` | 安卓启动格式的内核和 Sheng DTB，刷入 `boot_b` |
| `rootfs-popos-26.04-cosmic-sheng-linux.img` | Android sparse ext4 根镜像，展开为 20 GiB，刷入 `linux` |
| `SHA256SUMS` | 两个可刷入文件的 SHA‑256 |
| `apt-local/` | 带签名的本地 APT 仓库，内含内核、固件、音频配置和设备服务包 |

## 在 GitHub Actions 构建

1. 打开 [Build Pop!_OS for Sheng](https://github.com/Skylarrkuo/popos-sheng/actions/workflows/build.yml)，或在自己的 Fork 中进入同名工作流。
2. 点击 **Run workflow**，选择分支和需要的选项。构建前会自动下载并校验 ISO、内核源码、固件和设备包。
3. 构建完成后，在运行详情的 **Artifacts** 下载产物。`sheng-popos-26.04-arm64-images` 包含启动镜像和压缩根镜像，`sheng-popos-26.04-arm64-build` 包含本地 APT 仓库、包清单与日志。

| 输入 | 默认值 | 用途 |
| --- | --- | --- |
| `iso_url` | 留空 | 使用固定的 System76 官方 ISO。也可填写指向同一文件的 HTTPS 镜像，SHA‑256 必须与 [sources.tsv](sources.tsv) 一致 |
| `upload_images` | `true` | 保存可刷入的镜像产物。关闭时仍完成构建并保留设备包和日志 |
| `qemu_smoke_test` | `true` | 用通用 ARM64 QEMU 检查内核能进入 Pop!_OS 用户空间 |

云端根镜像使用 Zstandard 压缩。下载并解开 Artifact 的 ZIP 后，在 Linux 或 WSL 进入文件所在目录，依次校验下载件、解压和核对最终刷机文件。

```bash
sha256sum -c SHA256SUMS.download
zstd -d rootfs-popos-26.04-cosmic-sheng-linux.img.zst
sha256sum -c SHA256SUMS
```

### 输入版本

[sources.tsv](sources.tsv) 固定了 System76 的 ISO、Sheng 7.2.6 内核、适配源码和固件的下载来源与 SHA‑256。[device-sources.tsv](device-sources.tsv) 列出设备服务包。更新其中一项时，请把来源、版本和校验值一起核对。构建期间的基础软件包由 Pop!_OS 和 Ubuntu 的签名 APT 软件源提供，实际版本记录在 `packages.tsv`。

## 本地构建

推荐 Ubuntu 24.04，原生 ARM64 或 x86‑64 均可。x86‑64 主机需要静态 ARM64 QEMU。临时工作目录和仓库输出目录均需留出足够空间，完整构建建议预留至少 25 GiB。

```bash
git clone https://github.com/Skylarrkuo/popos-sheng.git
cd popos-sheng

sudo apt-get update
sudo apt-get install -y bc bison build-essential clang cpio curl device-tree-compiler \
  dpkg-dev e2fsprogs file flex gnupg kmod libelf-dev libssl-dev lld llvm lz4 \
  python3 rsync squashfs-tools xz-utils zstd android-sdk-libsparse-utils
# x86-64 主机另外安装 qemu-user-static。
bash scripts/fetch-inputs.sh
sudo bash scripts/build-kernel.sh
sudo bash scripts/prepare-rootfs.sh
sudo bash scripts/build-device-packages.sh
sudo bash scripts/build-image.sh
sudo bash scripts/publish-local-apt.sh
```

Windows 也可以用 PowerShell 7 和 WSL 2 的 `Ubuntu-24.04`。在 WSL 安装上述依赖及 `qemu-user-static`，将官方 `pop-os_26.04_arm64_generic_1.iso` 放到仓库的上一级，在 PowerShell 进入项目目录后执行以下命令。构建日志会在当前终端显示。

```powershell
pwsh -File .\Fetch-Inputs.ps1
pwsh -File .\Build-Visible.ps1
```

本地输出在 `out/`。Linux 构建可通过 `SHENG_POP_ISO` 指向已下载的 ISO，通过 `SHENG_POP_ISO_URL` 指定同一固定文件的下载镜像。`SHENG_POP_WORK` 用来选择临时目录，修改输入版本时请使用新的工作目录。`SHENG_POP_JOBS` 调整内核编译并发数。`SHENG_POP_QEMU_AARCH64` 可指定静态用户态模拟器的绝对路径。

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

已在平板上调试的三档 CPU 配置位于 [设备覆盖文件](scripts/overlays/)，COSMIC「关于」的硬件信息修复位于 [源码补丁](patches/cosmic-settings-sheng-about.patch)。这两项需在刷入后单独部署，基础镜像使用原版 COSMIC 设置与默认电源后端。

## 致谢与第三方来源

- [code002-2/ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng) 的设备构建方案、内核配置、ALSA UCM 和 Android 启动包制作，为本项目提供了移植基础。[Xiaomi Pad 6S Pro Linux 移植](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux) 提供了安装与双系统文档。
- [map220v](https://github.com/map220v) 推进了 Sheng 的主线 Linux、设备树和 TWRP 适配。[alghiffaryfa19](https://github.com/alghiffaryfa19/Linux-xiaomi-sheng) 的构建项目和设备包为音频、输入及传感器的适配提供了基础。
- [ianchb/sm8550-mainline](https://github.com/ianchb/sm8550-mainline)、[debian-sheng](https://github.com/ianchb/debian-sheng) 与 [sheng-firmware](https://github.com/ianchb/sheng-firmware) 提供了内核分支、设备功能包与固件来源。
- 感谢 Dylan Van Assche 和 SSC 后端贡献者维护传感器支持，感谢 System76 和 COSMIC 社区提供官方 ARM64 根系统、桌面和软件源。 [iio-sensor-proxy](https://gitlab.freedesktop.org/hadess/iio-sensor-proxy) · [System76 官方下载](https://system76.com/download-pop/)

Git 历史保留构建代码、配置和来源清单。ISO、固件、第三方软件包、签名私钥及刷机镜像在构建时获取或生成。各第三方组件适用其上游许可，固件归相应权利人。Linux 内核源码与配置见主线移植仓库，`mkbootimg` 源自 AOSP。 [AOSP mkbootimg](https://android.googlesource.com/platform/system/tools/mkbootimg/) · [COSMIC Settings](https://github.com/pop-os/cosmic-settings)
