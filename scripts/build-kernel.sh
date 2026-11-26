#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
output=$repo/out
src=$work/kernel-src
obj=$work/kernel-build
port=$work/ubuntu-sheng
pool=$repo/apt-local/pool
archive=$repo/inputs/sm8550-mainline.tar.gz
mkdir -p "$output/kernel" "$pool"
install -d -m 0700 "$work"
exec 9>"$work/kernel.lock"
flock -n 9
exec > >(tee -a "$output/kernel-build.log") 2>&1
trap 'printf "Kernel build stopped at line %s\n" "$LINENO" >&2' ERR

echo '[Kernel 1/4] Unpack and configure the SM8550 Sheng source'
archive_hash=$(sha256sum "$archive" | cut -d ' ' -f 1)
expected_hash=$(awk -F '\t' '$1 == "sm8550-mainline.tar.gz" {print $2}' "$repo/sources.tsv")
[[ $archive_hash == "$expected_hash" ]]
if [[ ! -f $src/.archive-sha256 ]]; then
    kernel_stage=$(mktemp -d "$work/kernel-source.XXXXXXXX")
    tar --extract --gzip --file "$archive" --strip-components=1 --no-same-owner -C "$kernel_stage"
    test -s "$kernel_stage/arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dts"
    printf '%s\n' "$archive_hash" > "$kernel_stage/.archive-sha256"
    mv -T "$kernel_stage" "$src"
fi
[[ $(cat "$src/.archive-sha256") == "$archive_hash" ]]
if [[ ! -f $port/sm8550.config ]]; then
    port_hash=$(awk -F '\t' '$1 == "ubuntu-sheng.tar.gz" {print $2}' "$repo/sources.tsv")
    printf '%s  %s\n' "$port_hash" "$repo/inputs/ubuntu-sheng.tar.gz" | sha256sum -c -
    mkdir -p "$port"
    tar --extract --gzip --file "$repo/inputs/ubuntu-sheng.tar.gz" --strip-components=1 --no-same-owner -C "$port"
fi
mkdir -p "$obj"
if [[ ! -s $obj/.config ]]; then
    install -m 0644 "$port/sm8550.config" "$obj/.config"
    "$src/scripts/config" --file "$obj/.config" --disable LOCALVERSION_AUTO \
        --enable DEBUG_INFO_NONE --disable DEBUG_INFO_BTF --disable DEBUG_INFO_BTF_MODULES
fi
make_args=(-C "$src" O="$obj" ARCH=arm64 LLVM=1 LOCALVERSION=-poposheng1)
make "${make_args[@]}" olddefconfig
for option in EFI_PARTITION EXT4_FS SCSI_UFSHCD SCSI_UFS_QCOM PHY_QCOM_QMP_UFS; do
    grep -Fx "CONFIG_$option=y" "$obj/.config"
done

echo '[Kernel 2/4] Compile Image.gz, the tablet DTB, and ARM64 kernel modules'
make "${make_args[@]}" -j"${SHENG_POP_JOBS:-8}" Image.gz qcom/sm8550-xiaomi-sheng.dtb modules
kver=$(make -s "${make_args[@]}" kernelrelease)
image=$obj/arch/arm64/boot/Image.gz
dtb=$obj/arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb
[[ $kver == 7.2.6* && $kver == *-poposheng1 ]]
gzip -t "$image"
fdtget -t s "$dtb" / compatible | grep -F 'xiaomi,sheng'

echo '[Kernel 3/4] Package the native kernel and its matching module tree'
pkg=$(mktemp -d "$work/kernel-package.XXXXXXXX")
trap 'rm -r -- "$pkg"' EXIT
make "${make_args[@]}" -j"${SHENG_POP_JOBS:-8}" INSTALL_MOD_PATH="$pkg" INSTALL_MOD_STRIP=1 modules_install
rm -f -- "$pkg/lib/modules/$kver/build" "$pkg/lib/modules/$kver/source"
depmod -F "$obj/System.map" -b "$pkg" "$kver"
test -s "$pkg/lib/modules/$kver/modules.dep"
mkdir -p "$pkg/usr/lib"
mv "$pkg/lib/modules" "$pkg/usr/lib/"
rmdir "$pkg/lib"
install -Dm 0644 "$image" "$pkg/boot/vmlinuz-$kver"
install -Dm 0644 "$dtb" "$pkg/boot/dtb-$kver.dtb"
install -Dm 0644 "$obj/System.map" "$pkg/boot/System.map-$kver"
install -Dm 0644 "$obj/.config" "$pkg/boot/config-$kver"
mkdir "$pkg/DEBIAN"
cat > "$pkg/DEBIAN/control" <<EOF
Package: linux-image-popos-sheng
Version: $kver
Architecture: arm64
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Section: kernel
Priority: optional
Description: SM8550 kernel and matched modules for Xiaomi Pad 6S Pro
 Built from the Sheng mainline port for the device's Android boot image path.
EOF
deb=$pool/linux-image-popos-sheng_${kver}_arm64.deb
dpkg-deb -Zxz -z3 --build --root-owner-group "$pkg" "$deb.partial"
mv "$deb.partial" "$deb"

echo '[Kernel 4/4] Pack a stock-ABL Android boot image for the existing linux partition'
cat "$image" "$dtb" > "$work/Image.gz-dtb_sheng"
python3 "$port/mkbootimg" --kernel "$work/Image.gz-dtb_sheng" \
    --cmdline 'root=PARTLABEL=linux rootwait rw fsck.repair=yes' \
    --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 \
    --pagesize 4096 --id -o "$output/boot-popos-sheng-dual.img.partial"
mv "$output/boot-popos-sheng-dual.img.partial" "$output/boot-popos-sheng-dual.img"
install -m 0644 "$image" "$dtb" "$output/kernel/"
install -m 0644 "$obj/.config" "$output/kernel/config-$kver"
printf '%s\n' "$kver" > "$output/kernelrelease.txt"
printf '%s\n' "$(basename "$deb")" > "$work/kernel-deb.txt"
echo "Compiled Sheng kernel $kver"
