#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} != --private ]]; then
    exec unshare --mount --propagation private bash "$0" --private "$@"
fi
shift
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
iso_name=pop-os_26.04_arm64_generic_1.iso
default_iso=$repo/inputs/$iso_name
if [[ -f $repo/../$iso_name ]]; then default_iso=$repo/../$iso_name; fi
iso=${1:-${SHENG_POP_ISO:-$default_iso}}
iso_hash=$(awk -F '\t' -v name="$iso_name" '$1 == name {print $2}' "$repo/sources.tsv")
[[ $iso_hash =~ ^[[:xdigit:]]{64}$ ]]
work=${SHENG_POP_WORK:-/var/tmp/popos-sheng-26.04}
output=$repo/out
root=$work/rootfs
image=$work/rootfs.ext4
iso_mount=$work/iso
mkdir -p "$output"
install -d -m 0700 "$work"
exec 9>"$work/rootfs.lock"
flock -n 9
exec > >(tee -a "$output/prepare-rootfs.log") 2>&1

cleanup() {
    if mountpoint -q "$root"; then umount "$root"; fi
    if mountpoint -q "$iso_mount"; then umount "$iso_mount"; fi
}
trap cleanup EXIT

if [[ -f $work/iso-ready && -s $image ]]; then
    echo 'Official Pop!_OS root filesystem is already prepared'
    exit 0
fi
echo '[Rootfs 1/2] Verify official Pop!_OS 26.04 ARM64 ISO'
printf '%s  %s\n' "$iso_hash" "$iso" | sha256sum -c -
mkdir -p "$root" "$iso_mount"
mount -o loop,ro "$iso" "$iso_mount"
mapfile -t squashfs < <(find "$iso_mount" -name filesystem.squashfs -type f)
[[ ${#squashfs[@]} == 1 ]]
install -m 0644 "$(dirname "${squashfs[0]}")/filesystem.manifest" "$work/iso-packages.tsv"

echo '[Rootfs 2/2] Extract the official COSMIC system into a 20 GiB ext4 image'
rm -f -- "$image.partial"
truncate -s 20G "$image.partial"
mkfs.ext4 -q -F -L popos-sheng "$image.partial"
mount -o loop,discard "$image.partial" "$root"
unsquashfs -no-progress -processors "${SHENG_POP_UNSQUASH_JOBS:-6}" -f -d "$root" "${squashfs[0]}"
grep -Fx 'PRETTY_NAME="Pop!_OS 26.04 LTS"' "$root/etc/os-release"
file "$root/usr/bin/cosmic-comp" | grep -qi 'ARM aarch64'
test -x "$root/usr/bin/cosmic-session"
df -h "$root"
sync -f "$root"
umount "$root"
umount "$iso_mount"
rm -f -- "$work/device-configured"
mv "$image.partial" "$image"
touch "$work/iso-ready"
echo 'Official Pop!_OS COSMIC root filesystem prepared'
