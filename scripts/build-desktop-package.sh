#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
src=$repo/scripts/overlays/desktop
stage=$1/desktop

install -d -m 0755 "$stage/DEBIAN"
cat > "$stage/DEBIAN/control" <<'EOF'
Package: popos-sheng-desktop
Version: 1.0
Architecture: all
Maintainer: Pop!_OS Sheng local build <local@sheng.invalid>
Depends: python3, python3-gi, gir1.2-gtk-4.0, pkexec, cosmic-randr, libssc,
 fcitx5, fcitx5-pinyin, fcitx5-config-qt, fcitx5-frontend-gtk3,
 fcitx5-frontend-gtk4, fcitx5-frontend-qt5, fcitx5-frontend-qt6, fonts-noto-cjk
Section: x11
Priority: optional
Description: Sheng desktop integration for Pop!_OS COSMIC
 Configures Chinese Pinyin, touchscreen rotation and an Android restart
 launcher. The Android action requires calibration for the individual tablet.
EOF

put() {
    install -D -m "$1" "$src/$2" "$stage/$3"
}

put 0755 rotation/sheng-screen-rotation usr/bin/sheng-screen-rotation
put 0755 rotation/sheng-rotation-indicator usr/libexec/sheng-rotation-indicator
put 0755 rotation/sheng-rotation-sensor-stream usr/libexec/sheng-rotation-sensor-stream
put 0644 rotation/sheng-screen-rotation.desktop usr/share/applications/sheng-screen-rotation.desktop
for unit in sheng-rotation-sensor.socket sheng-rotation-sensor@.service; do
    put 0644 "rotation/$unit" "usr/lib/systemd/system/$unit"
done
install -d -m 0755 "$stage/usr/lib/systemd/system/sockets.target.wants" "$stage/usr/lib/sysusers.d"
ln -s ../sheng-rotation-sensor.socket "$stage/usr/lib/systemd/system/sockets.target.wants/"
printf 'g sheng-rotation -\n' > "$stage/usr/lib/sysusers.d/popos-sheng-desktop.conf"

install -d -m 0755 "$stage/usr/lib/systemd/user/cosmic-session.target.wants"
for unit in rotation/sheng-screen-rotation.service rotation/sheng-rotation-indicator.service input/fcitx5-cosmic.service; do
    name=${unit##*/}
    put 0644 "$unit" "usr/lib/systemd/user/$name"
    ln -s "../$name" "$stage/usr/lib/systemd/user/cosmic-session.target.wants/"
done
put 0644 input/65-fcitx5.conf usr/lib/environment.d/65-sheng-fcitx5.conf
for config in config profile conf/classicui.conf conf/pinyin.conf; do
    put 0644 "input/$config" "etc/skel/.config/fcitx5/$config"
done
for asset in "$src"/input/Sheng-Light/*; do
    name=${asset##*/}
    put 0644 "input/Sheng-Light/$name" "usr/share/fcitx5/themes/Sheng-Light/$name"
done

put 0755 android/sheng-android-menu usr/bin/sheng-android-menu
put 0755 android/sheng-reboot-android usr/libexec/sheng-reboot-android
put 0644 android/com.xiaomi.sheng.AndroidRestart.desktop usr/share/applications/com.xiaomi.sheng.AndroidRestart.desktop
put 0644 android/com.xiaomi.sheng.reboot-android.policy usr/share/polkit-1/actions/com.xiaomi.sheng.reboot-android.policy

for program in "$stage"/usr/bin/sheng-* "$stage"/usr/libexec/sheng-rotation-*; do
    python3 -c 'import sys; from pathlib import Path; p=Path(sys.argv[1]); compile(p.read_bytes(), str(p), "exec")' "$program"
done
bash -n "$stage/usr/libexec/sheng-reboot-android"
dpkg-deb -Zxz -z3 --build --root-owner-group "$stage" "$1"
