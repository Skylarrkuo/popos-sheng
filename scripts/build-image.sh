#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != --private ]]; then
    exec unshare --mount --propagation private bash "$0" --private "$@"
fi
shift
mode=${1:-full}
[[ $mode == full || $mode == --configure-only ]]
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
root=$work/rootfs
image=$work/rootfs.ext4
output=$repo/out
pool=$repo/apt-local/pool
binfmt=/proc/sys/fs/binfmt_misc
registration=$binfmt/popos-sheng-aarch64
stage=/var/tmp/popos-sheng-packages
apt_build_config=$root/etc/apt/apt.conf.d/99zz-popos-sheng-build
username=starin
sparse=rootfs-popos-26.04-cosmic-sheng-linux.img
boot=boot-popos-sheng-dual.img

test -s "$image"
test -f "$work/iso-ready"
test -s "$work/device-debs.txt"
exec 9>"$work/rootfs.lock"
flock -n 9
exec > >(tee -a "$output/image-build.log") 2>&1
trap 'printf "Image build stopped at line %s\n" "$LINENO" >&2' ERR

mounted=()
registered=0
release_mounts() {
    local index
    for ((index=${#mounted[@]}-1; index>=0; index--)); do
        umount "${mounted[index]}" || return 1
    done
    mounted=()
}
cleanup() {
    if mountpoint -q "$root"; then rm -f -- "$apt_build_config"; fi
    release_mounts || :
    if ((registered)) && [[ -e $registration ]]; then echo -1 > "$registration"; fi
}
trap cleanup EXIT
attach() {
    mount "$@"
    mounted+=("${@: -1}")
}
inside() {
    chroot "$root" /usr/bin/env LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"
}

if [[ $(uname -m) != aarch64 && ! -f $binfmt/qemu-aarch64 ]]; then
    emulator=${SHENG_POP_QEMU_AARCH64:-$(command -v qemu-aarch64-static || :)}
    if [[ -z $emulator ]]; then
        echo 'Install qemu-user-static or set SHENG_POP_QEMU_AARCH64 to a static ARM64 emulator.' >&2
        exit 1
    fi
    test -x "$emulator"
    magic='\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00'
    mask='\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff'
    printf ':popos-sheng-aarch64:M::%s:%s:%s:OCF\n' "$magic" "$mask" "$emulator" > "$binfmt/register"
    registered=1
fi

attach -o loop,discard "$image" "$root"
attach -t tmpfs -o mode=0755 tmpfs "$root/dev"
mknod -m 0666 "$root/dev/null" c 1 3
mknod -m 0666 "$root/dev/zero" c 1 5
mknod -m 0666 "$root/dev/random" c 1 8
mknod -m 0666 "$root/dev/urandom" c 1 9
mknod -m 0666 "$root/dev/tty" c 5 0
mkdir "$root/dev/pts"
ln -s pts/ptmx "$root/dev/ptmx"
ln -s /proc/self/fd "$root/dev/fd"
attach -t devpts -o newinstance,ptmxmode=0666,mode=0620 devpts "$root/dev/pts"
attach -t proc proc "$root/proc"
attach -t tmpfs -o mode=0755 tmpfs "$root/run"
[[ $(inside dpkg --print-architecture) == arm64 ]]
rm -f "$root/etc/resolv.conf"
cp -L /etc/resolv.conf "$root/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$root/usr/sbin/policy-rc.d"
chmod 0755 "$root/usr/sbin/policy-rc.d"

if [[ ! -f $work/device-configured ]]; then
    echo '[Image 1/4] Install the firmware, hardware services, and status utilities on Pop!_OS'
    sed -i -e 's|^URIs: http://ports.ubuntu.com/|URIs: https://ports.ubuntu.com/|' \
        -e 's|^URIs: http://apt.pop-os.org/|URIs: https://apt.pop-os.org/|' "$root/etc/apt/sources.list.d/"*.sources
    apt_options=(-o Acquire::Retries=1 -o Acquire::https::Timeout=20)
    # The target will refresh these optional catalogs natively after boot.
    printf '#clear APT::Update::Post-Invoke-Success;\n' > "$apt_build_config"
    if ! inside apt-get "${apt_options[@]}" update --error-on=any; then
        echo 'Refresh signed Ubuntu ARM64 indexes for the device package dependencies'
        inside apt-get "${apt_options[@]}" \
            -o Dir::Etc::SourceList=/etc/apt/sources.list.d/system.sources \
            -o Dir::Etc::SourceParts=- -o APT::Get::List-Cleanup=0 update --error-on=any
    fi
    rm -f -- "$apt_build_config"
    install -d -m 0755 "$root$stage"
    requested=()
    while IFS= read -r name; do
        [[ $name =~ ^[a-zA-Z0-9._+-]+\.deb$ ]]
        install -m 0644 "$pool/$name" "$root$stage/$name"
        requested+=("$stage/$name")
    done < "$work/device-debs.txt"
    inside apt-get "${apt_options[@]}" --no-remove --no-install-recommends -y install \
        "${requested[@]}" upower v4l-utils libcamera-tools
    for deb in "${requested[@]}"; do rm -- "$root$deb"; done
    rmdir "$root$stage"

    # The Android boot image is maintained separately from the Ubuntu kernel hooks.
    install -d -m 0755 "$root/etc/flash-kernel"
    printf 'none\n' > "$root/etc/flash-kernel/machine"
    inside apt-get "${apt_options[@]}" --no-install-recommends -y install \
        power-profiles-daemon system76-power-

    echo '[Image 2/4] Set up the COSMIC greeter and the existing dual-boot linux partition'
    inside id "$username" >/dev/null 2>&1 || inside useradd -m -s /bin/bash -G sudo "$username"
    printf '%s:%s\n' "$username" "${SHENG_INITIAL_PASSWORD:-$username}" | inside chpasswd
    inside passwd -l root
    printf 'Username: %s\nInitial password: %s\n' "$username" "${SHENG_INITIAL_PASSWORD:-$username}" > "$output/login.txt"
    printf 'popos-sheng\n' > "$root/etc/hostname"
    if ! grep -Eq '^127\.0\.1\.1[[:space:]]+popos-sheng$' "$root/etc/hosts"; then
        printf '127.0.1.1 popos-sheng\n' >> "$root/etc/hosts"
    fi
    printf 'PARTLABEL=linux / ext4 defaults,x-systemd.growfs 0 1\n' > "$root/etc/fstab"
    systemctl --root "$root" mask systemd-networkd-wait-online.service
    printf 'CHASSIS=tablet\nHARDWARE_VENDOR=Xiaomi\nHARDWARE_MODEL="Pad 6S Pro 12.4"\n' > "$root/etc/machine-info"
    sed -i -E 's/^# ?(zh_CN.UTF-8 UTF-8)$/\1/' "$root/etc/locale.gen"
    inside locale-gen zh_CN.UTF-8
    printf 'LANG=zh_CN.UTF-8\n' > "$root/etc/default/locale"
    printf 'LANG=zh_CN.UTF-8\n' > "$root/etc/locale.conf"

    test -f "$root/usr/lib/systemd/system/cosmic-greeter.service"
    test -f "$root/usr/share/wayland-sessions/cosmic.desktop"
    ln -sfn /lib/systemd/system/cosmic-greeter.service "$root/etc/systemd/system/display-manager.service"
    systemctl --root="$root" set-default graphical.target
    systemctl --root="$root" enable NetworkManager.service bluetooth.service adsprpcd-sensorspd.service sheng-devauth.service
    systemctl --root="$root" mask casper-md5check.service
    touch "$work/device-configured"
fi

if [[ $mode == full ]]; then
    echo '[Image 3/4] Install and audit the newly compiled Sheng kernel beside COSMIC'
    read -r kernel_deb < "$work/kernel-deb.txt"
    read -r release < "$output/kernelrelease.txt"
    [[ $kernel_deb == "linux-image-popos-sheng_${release}_arm64.deb" ]]
    install -Dm 0644 "$pool/$kernel_deb" "$root$stage/$kernel_deb"
    inside dpkg -i "$stage/$kernel_deb"
    rm -- "$root$stage/$kernel_deb"
    rmdir "$root$stage"
    test -s "$root/usr/lib/modules/$release/modules.dep"
    cmp "$root/boot/dtb-$release.dtb" "$output/kernel/sm8550-xiaomi-sheng.dtb"
    cmp "$root/boot/vmlinuz-$release" "$output/kernel/Image.gz"
    for executable in usr/bin/adsprpcd usr/libexec/iio-sensor-proxy usr/bin/xiaomi_devauth; do
        test -x "$root/$executable"
        [[ $(stat -c '%u:%g' "$root/$executable") == 0:0 ]]
    done
    for firmware in updates/qcom/a740_sqe.fw updates/ath12k/WCN7850/hw2.0/board-2.bin \
        updates/cirrus/blh-cs35l43-dsp1-spk-prot.wmfw fpcsheng.elf; do
        test -s "$root/usr/lib/firmware/$firmware"
    done
    test -s "$root/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so"
    test -s "$root/usr/share/alsa/ucm2/Xiaomi/sheng/HiFi.conf"
    test -L "$root/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf"
    grep -Fxq snd_soc_wcd938x "$root/usr/lib/modules-load.d/popos-sheng-audio.conf"
    test -s "$root/usr/lib/firmware/qcom/sm8550/sheng/devauth.mbn"
    grep -Fxq none "$root/etc/flash-kernel/machine"
    grep -Fxq 'PARTLABEL=linux / ext4 defaults,x-systemd.growfs 0 1' "$root/etc/fstab"
    test "$(readlink "$root/etc/systemd/system/display-manager.service")" = /lib/systemd/system/cosmic-greeter.service
    inside /lib/ld-linux-aarch64.so.1 --list /usr/bin/cosmic-comp > "$output/cosmic-library-check.txt"
    inside dpkg --audit | tee "$output/dpkg-audit.txt"
    test ! -s "$output/dpkg-audit.txt"
    inside apt-get check
    packages=(cosmic-session cosmic-comp cosmic-greeter mesa-vulkan-drivers pop-desktop upower power-profiles-daemon \
        v4l-utils libcamera-tools libspa-0.2-libcamera)
    while IFS= read -r name; do
        packages+=("$(dpkg-deb -f "$pool/$name" Package)")
    done < "$work/device-debs.txt"
    inside dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\t${db:Status-Status}\n' \
        "${packages[@]}" linux-image-popos-sheng > "$output/packages.tsv"
    awk -F '\t' '$4 != "installed" {exit 1}' "$output/packages.tsv"
fi

inside apt-get clean
rm -f "$apt_build_config" "$root/usr/sbin/policy-rc.d" "$root/etc/resolv.conf" "$root/var/lib/systemd/random-seed"
ln -s /run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
printf 'uninitialized\n' > "$root/etc/machine-id"
ln -sfn /etc/machine-id "$root/var/lib/dbus/machine-id"
sync -f "$root"
fstrim "$root" || :
release_mounts
if [[ $mode == --configure-only ]]; then
    echo 'The COSMIC system and device configuration are ready for the matching kernel'
    exit 0
fi

echo '[Image 4/4] Check ext4, pack the sparse image, and verify the round trip'
e2fsck -fn "$image"
if [[ ${SHENG_POP_COMPRESS_ROOTFS:-0} == 1 ]]; then
    packed=$sparse.zst
    img2simg "$image" - 4096 | zstd -q -T2 -3 > "$output/$packed.partial"
    zstd -dc -- "$output/$packed.partial" | python3 "$repo/scripts/verify-images.py" \
        "$output" --sparse - --raw-rootfs "$image"
    mv "$output/$packed.partial" "$output/$packed"
    (
        cd "$output"
        sha256sum -- "$boot" "$packed" > SHA256SUMS.download
        sha256sum -- "$boot" > SHA256SUMS
        digest=$(zstd -dc -- "$packed" | sha256sum)
        printf '%s  %s\n' "${digest%% *}" "$sparse" >> SHA256SUMS
    )
else
    packed=$sparse
    img2simg "$image" "$output/$sparse.partial" 4096
    python3 "$repo/scripts/verify-images.py" "$output" \
        --sparse "$output/$sparse.partial" --raw-rootfs "$image"
    mv "$output/$sparse.partial" "$output/$sparse"
    (cd "$output" && sha256sum -- "$boot" "$sparse" > SHA256SUMS && sha256sum -c SHA256SUMS)
fi
cp "$repo/"{sources.tsv,device-sources.tsv} "$output/"
cp "$work/iso-packages.tsv" "$output/"
ls -lh "$output/$boot" "$output/$packed"
