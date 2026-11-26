#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
pool=$repo/apt-local/pool
install -d -m 0755 "$pool"
install -d -m 0700 "$work"
stage=$(mktemp -d "$work/device-packages.XXXXXXXX")
trap 'rm -r -- "$stage"' EXIT

check_input() {
    local name=$1 digest
    digest=$(awk -F '\t' -v name="$name" '$1 == name {print $2}' "$repo/sources.tsv")
    [[ $digest =~ ^[[:xdigit:]]{64}$ ]]
    printf '%s  %s\n' "$digest" "$repo/inputs/$name" | sha256sum -c -
}

device_packages=()
while IFS=$'\t' read -r name digest url; do
    [[ $name != asset ]] || continue
    [[ $name =~ ^[a-zA-Z0-9._+-]+\.deb$ && $digest =~ ^[[:xdigit:]]{64}$ ]]
    deb=$repo/inputs/debs/$name
    printf '%s  %s\n' "$digest" "$deb" | sha256sum -c -
    case $(dpkg-deb -f "$deb" Architecture) in arm64|all) ;; *) exit 1;; esac
    package=$stage/vendor/$name
    mkdir -p "$package"
    dpkg-deb --raw-extract "$deb" "$package"
    for executable in usr/bin/adsprpcd usr/libexec/iio-sensor-proxy usr/bin/monitor-sensor usr/bin/ssccli; do
        if [[ -f $package/$executable && ! -L $package/$executable ]]; then
            chmod 0755 "$package/$executable"
        fi
    done
    # Several older upstream tar members carry the GitHub runner's numeric owner.
    dpkg-deb -Zxz -z3 --build --root-owner-group "$package" "$pool/$name.partial"
    mv "$pool/$name.partial" "$pool/$name"
    device_packages+=("$name")
done < "$repo/device-sources.tsv"

check_input ubuntu-sheng.tar.gz
check_input sheng-firmware.tar.gz
mkdir -p "$stage/port" "$stage/firmware/DEBIAN" "$stage/audio/DEBIAN"
tar -xzf "$repo/inputs/ubuntu-sheng.tar.gz" --strip-components=1 --no-same-owner -C "$stage/port"
firmware=$stage/firmware/usr/lib/firmware
mkdir -p "$firmware/updates"
tar -xzf "$repo/inputs/sheng-firmware.tar.gz" --strip-components=1 --no-same-owner -C "$firmware/updates"
mv "$firmware/updates/fpcsheng.elf" "$firmware/fpcsheng.elf"
test -s "$firmware/fpcsheng.elf"
test -d "$firmware/updates/ath12k/WCN7850"
test -d "$firmware/updates/cirrus"
mkdir -p "$stage/audio/usr/share/alsa"
cp -a "$stage/port/alsa-xiaomi-sheng/usr/share/alsa/ucm2" "$stage/audio/usr/share/alsa/"

cat > "$stage/firmware/DEBIAN/control" <<'EOF'
Package: firmware-popos-sheng
Version: 1.0+053da477
Architecture: all
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Section: kernel
Priority: optional
Provides: firmware-xiaomi-sheng
Description: Firmware overlays for Xiaomi Pad 6S Pro
 Device-specific firmware is loaded through the Linux firmware updates path.
EOF
cat > "$stage/audio/DEBIAN/control" <<'EOF'
Package: alsa-ucm-popos-sheng
Version: 1.0+eaff0351
Architecture: all
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Depends: alsa-ucm-conf
Section: sound
Priority: optional
Description: ALSA UCM profiles for the Xiaomi Pad 6S Pro audio card
 Profiles sourced from the Sheng Ubuntu port.
EOF
firmware_deb=firmware-popos-sheng_1.0+053da477_all.deb
audio_deb=alsa-ucm-popos-sheng_1.0+eaff0351_all.deb
dpkg-deb -Zxz -z3 --build --root-owner-group "$stage/firmware" "$pool/$firmware_deb.partial"
dpkg-deb -Zxz -z3 --build --root-owner-group "$stage/audio" "$pool/$audio_deb.partial"
mv "$pool/$firmware_deb.partial" "$pool/$firmware_deb"
mv "$pool/$audio_deb.partial" "$pool/$audio_deb"
device_packages+=("$firmware_deb" "$audio_deb")
printf '%s\n' "${device_packages[@]}" > "$work/device-debs.txt"
