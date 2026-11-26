# 小米平板 6S Pro · Pop!_OS 26.04 COSMIC

面向小米平板 6S Pro 12.4（`sheng`、骁龙 8 Gen 2、ARM64）的本地构建项目。根系统来自 System76 官方 Pop!_OS 26.04 LTS ARM64 通用 ISO，默认桌面和登录界面分别使用 COSMIC 和 COSMIC Greeter。启动采用小米原有 ABL、B 槽 Android v0 `boot.img`、独立 `linux` 根分区。

## 构建输入

- [System76 官方镜像](https://system76.com/download-pop/)提供 COSMIC、Pop 软件源、Mesa 和基础系统。构建前核验官方 SHA‑256。
- [ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng)提供 Sheng 7.2.6 编译配置、设备固件和服务的配套方案、UCM2 音频配置及 `mkbootimg`。
- [Xiaomi Pad 6S Pro Linux 移植](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux)提供设备适配与双系统安装约定。

`sources.tsv` 和 `device-sources.tsv` 记录具体提交、下载位置和 SHA‑256。ISO、固件、第三方包、私有 APT 签名密钥和大体积构建产物保存在本地工作区或 WSL 工作目录。

## 重新构建

将 `pop-os_26.04_arm64_generic_1.iso` 放在项目目录的上一级，在 Windows PowerShell 7 进入本项目。构建使用 WSL 2 的 `Ubuntu-24.04`。

```powershell
pwsh -File .\Fetch-Inputs.ps1
pwsh -File .\Build-Visible.ps1
```

内核目标为 `Image.gz`、`sm8550-xiaomi-sheng.dtb` 和匹配的模块树。WSL 需要 Clang、LLVM、LLD、make、bison、flex、`libelf-dev`、`libssl-dev`、bc、cpio、kmod、lz4、zstd、dtc、squashfs-tools、e2fsprogs、Android sparse 转换工具、dpkg-dev、GnuPG 和 ARM64 QEMU 用户态解释器。`SHENG_POP_WORK` 可改变 WSL 工作目录，`SHENG_POP_JOBS` 可调整内核并行数。

WSL 的 Android sparse 工具和设备树工具分别由 `android-sdk-libsparse-utils` 和 `device-tree-compiler` 提供。通用 ARM64 启动测试使用 `qemu-system-arm` 软件包中的 `qemu-system-aarch64`。

## 产物与本地仓库

| 路径 | 用途 |
| --- | --- |
| `out/boot-popos-sheng-dual.img` | 可刷入 `boot_b` 的 Android v0 镜像 |
| `out/rootfs-popos-26.04-cosmic-sheng-linux.img` | 可刷入 `linux` 的 Android sparse ext4 根镜像，展开为 20 GiB |
| `out/kernel/` | 本次编译的 `Image.gz`、Sheng DTB 和内核配置 |
| `out/SHA256SUMS` | 两个刷机文件的 SHA‑256 |
| `out/packages.tsv` | COSMIC、Mesa、内核和设备包版本 |
| `apt-local/` | 已签名的本地 APT 仓库，包含 ARM64 内核、固件、音频和设备服务包 |

本地 APT 仓库可整目录复制到平板，用 `popos-sheng-archive.gpg` 作为该源的 `signed-by` 公钥，源路径使用 `file:`，套件填写 `./`。签名密钥指纹见 `apt-local/SIGNING-KEY-FINGERPRINT.txt`。

## 手动刷入

以下命令以已建好独立 `linux` 分区的双系统布局为前提。刷机会覆盖现有 Linux 分区的系统和文件。先核对 `SHA256SUMS`，确认 `product` 为 `sheng`，`boot_b` 能容纳启动镜像，`linux` 容量至少为 **20 GiB**（`0x500000000`）。

```powershell
fastboot getvar product
fastboot getvar partition-size:boot_b
fastboot getvar partition-size:linux
fastboot erase dtbo_b
fastboot flash boot_b .\boot-popos-sheng-dual.img
fastboot -S 512M flash linux .\rootfs-popos-26.04-cosmic-sheng-linux.img
fastboot set_active b
fastboot getvar current-slot
fastboot reboot
```

初始用户名和密码见 `out/login.txt`。启动后由 systemd 按 `linux` 分区容量扩展 ext4。COSMIC 默认使用简体中文系统区域设置。

## 验证范围

构建检查包括 ARM64 内核、DTB、模块和启动文件一致性，COSMIC 会话及 Greeter、Mesa Freedreno、APT 依赖、ext4、稀疏镜像往返比对和 SHA‑256。通用 ARM64 QEMU 测试可以覆盖内核进入 Pop!_OS 用户空间。屏幕、触控、Adreno、Wi‑Fi、蓝牙、扬声器、相机、传感器、Pogo 键盘、触控笔、指纹和充电需要在本机逐项验收。

本次构建的 `out/qemu-smoke.log` 记录了 `7.2.6-sm8550-poposheng1` 挂载 ext4、进入 Pop!_OS 26.04 用户空间，并找到 COSMIC 会话文件。`out/local-apt-policy.txt` 记录了 APT 读取本地仓库后选中的内核包。

| 硬件 | 镜像适配组件 |
| --- | --- |
| 屏幕、触控和 Adreno 740 | Sheng DTB、MSM DRM、触控模块、面板固件、Adreno 固件和 Pop!_OS Mesa Freedreno |
| Wi‑Fi、蓝牙与 USB | `ath12k` WCN7850 固件、QCA 蓝牙固件、Qualcomm DWC3 和 Type‑C 内核驱动 |
| 扬声器和相机 | Cirrus 扬声器固件、Sheng ALSA UCM、Qualcomm CAMSS、PipeWire libcamera、V4L2 和 libcamera 工具 |
| 键盘、触控笔和传感器 | Pogo DevAuth、键盘与触控笔帮助程序、FastRPC、SSC 与 iio-sensor-proxy |
| 充电和指纹 | MIPPS 和充电模式服务、FPC1553 配套固件及 QTEE/fprintd 设备包 |
