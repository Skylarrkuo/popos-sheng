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
devauth=qcom/sm8550/sheng/devauth.mbn
install -d -m 0755 "$firmware/$(dirname "$devauth")"
ln -s "../../../updates/$devauth" "$firmware/$devauth"
test -s "$firmware/$devauth"
test -s "$firmware/fpcsheng.elf"
test -d "$firmware/updates/ath12k/WCN7850"
test -d "$firmware/updates/cirrus"
mkdir -p "$stage/audio/usr/share/alsa"
cp -a "$stage/port/alsa-xiaomi-sheng/usr/share/alsa/ucm2" "$stage/audio/usr/share/alsa/"
ucm=$stage/audio/usr/share/alsa/ucm2/conf.d/sm8550/Xiaomi-Pad6SPro.conf
ucm_target=../../Xiaomi/sheng/Xiaomi-Pad6SPro.conf
if [[ -L $ucm ]]; then
    test "$(readlink "$ucm")" = "$ucm_target"
else
    test "$(cat "$ucm")" = "$ucm_target"
    ln -sfn "$ucm_target" "$ucm"
fi
test -s "$ucm"
install -d -m 0755 "$stage/audio/usr/lib/modules-load.d"
printf 'snd_soc_wcd938x\n' > "$stage/audio/usr/lib/modules-load.d/popos-sheng-audio.conf"

install -d -m 0755 "$stage/platform/DEBIAN"
install -Dm0755 "$repo/scripts/overlays/popos-sheng-mipps-pd" \
    "$stage/platform/usr/libexec/popos-sheng-mipps-pd"
install -Dm0644 "$repo/scripts/overlays/mipps-pd.conf" \
    "$stage/platform/usr/lib/systemd/system/xiaomi-mipps-auth.service.d/sheng-pd.conf"

install -Dm0755 "$repo/scripts/overlays/popos-sheng-cpu-profile" \
    "$stage/platform/usr/libexec/popos-sheng-cpu-profile"
install -Dm0755 "$repo/scripts/overlays/sheng-cpu-resume" \
    "$stage/platform/usr/lib/systemd/system-sleep/sheng-cpu-resume"
install -Dm0644 "$repo/scripts/overlays/sheng-tuned-ppd.conf" \
    "$stage/platform/usr/share/popos-sheng/ppd.conf"
for profile in power-saver balanced performance; do
    profile_dir=$stage/platform/usr/lib/tuned/profiles/sheng-$profile
    install -d -m 0755 "$profile_dir"
    cat > "$profile_dir/tuned.conf" <<'EOF'
[script]
script=${i:PROFILE_DIR}/profile.sh
EOF
    cat > "$profile_dir/profile.sh" <<EOF
#!/bin/sh
exec /usr/libexec/popos-sheng-cpu-profile sheng-$profile "\$@"
EOF
    chmod 0755 "$profile_dir/profile.sh"
done

cat > "$stage/firmware/DEBIAN/control" <<'EOF'
Package: firmware-popos-sheng
Version: 1.0+053da477+poposheng1
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
Version: 1.0+eaff0351+poposheng1
Architecture: all
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Depends: alsa-ucm-conf
Section: sound
Priority: optional
Description: ALSA UCM profiles for the Xiaomi Pad 6S Pro audio card
 Profiles sourced from the Sheng Ubuntu port.
EOF
cat > "$stage/platform/DEBIAN/control" <<'EOF'
Package: popos-sheng-platform
Version: 1.1
Architecture: all
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Depends: xiaomi-mipps-auth, tuned-ppd, python3
Section: admin
Priority: optional
Description: Xiaomi Pad 6S Pro platform configuration for Pop!_OS
 Integrates MiPPS partner authentication and the Sheng CPU power profiles.
EOF
for component in firmware audio platform; do
    dpkg-deb -Zxz -z3 --build --root-owner-group "$stage/$component" "$stage"
done
for deb in "$stage"/*.deb; do
    mv -- "$deb" "$pool/"
    device_packages+=("$(basename "$deb")")
done
printf '%s\n' "${device_packages[@]}" > "$work/device-debs.txt"
