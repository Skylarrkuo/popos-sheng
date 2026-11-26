#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != --private ]]; then
    exec unshare --mount --propagation private bash "$0" --private "$@"
fi
shift
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
image=${1:-$work/rootfs.ext4}
root=$(mktemp -d /tmp/pop-sheng-root.XXXXXXXX)
trap 'if mountpoint -q "$root"; then umount "$root"; fi; rmdir "$root"' EXIT
mount -o loop,ro,noload "$image" "$root"

echo 'Display manager and COSMIC session'
ls -l "$root/etc/systemd/system/display-manager.service" "$root/etc/X11/default-display-manager" 2>/dev/null || :
find "$root/etc/greetd" "$root/usr/share/wayland-sessions" -maxdepth 1 -type f -printf '%P\n' 2>/dev/null || :
for path in usr/lib/systemd/system/cosmic-greeter.service etc/greetd/cosmic-greeter.toml usr/share/wayland-sessions/cosmic.desktop; do
    if [[ -f $root/$path ]]; then printf '\n%s\n' "$path"; cat "$root/$path"; fi
done

echo 'Existing non-system accounts'
awk -F: '$3 >= 1000 && $3 < 60000 {print $1, $3, $6}' "$root/etc/passwd"
echo 'APT source locations'
find "$root/etc/apt" -maxdepth 2 -type f \( -name '*.sources' -o -name '*.list' \) -exec grep -H -E '^(URIs:|Suites:|deb )' {} +
echo 'Installed device-facing software'
dpkg-query --admindir="$root/var/lib/dpkg" -W -f='${Package}\t${Version}\n' | \
    grep -E '^(cosmic-(greeter|session|comp)|mesa-vulkan-drivers|linux-firmware|network-manager|upower|bluez|iio-sensor-proxy|fprintd|pipewire|libspa-0.2-libcamera|locales|fonts-noto-cjk|als[a-z-]+|casper)\s' || :
find "$root/usr/lib" -type f \( -name libvulkan_freedreno.so -o -name '*dri.so' \) -printf '%P\n' | head -35
find "$root/usr/share/alsa/ucm2" -iname '*sheng*' -o -iname '*Pad6S*'
