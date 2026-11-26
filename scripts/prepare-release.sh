#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
out=$repo/out
release=$out/release
rootfs=rootfs-popos-26.04-cosmic-sheng-linux.img.zst
apt_archive=apt-local-arm64.tar.zst
boot=boot-popos-sheng-dual.img
limit=$((2 * 1024 * 1024 * 1024))
part_size=1900000000

cd "$out"
sha256sum -c SHA256SUMS.download
mkdir "$release"
cp -- "$boot" SHA256SUMS packages.tsv "$release/"

add_archive() {
    local source=$1 name digest reconstructed
    name=$(basename "$source")
    if (( $(stat -c %s "$source") < limit )); then
        mv -- "$source" "$release/$name"
        (cd "$release" && sha256sum -- "$name") >> "$release/SHA256SUMS.download"
        return
    fi

    split --bytes="$part_size" --numeric-suffixes=1 --suffix-length=3 -- \
        "$source" "$release/$name.part-"
    local parts=("$release/$name.part-"*)
    digest=$(sha256sum -- "$source")
    reconstructed=$(cat -- "${parts[@]}" | sha256sum)
    [[ ${digest%% *} == "${reconstructed%% *}" ]]
    (cd "$release" && sha256sum -- "$name.part-"*) >> "$release/SHA256SUMS.download"
    rm -- "$source"
}

(cd "$release" && sha256sum -- "$boot" packages.tsv SHA256SUMS > SHA256SUMS.download)
add_archive "$rootfs"
tar -C "$repo" -cf - apt-local | zstd -q -T2 -3 -o "$apt_archive"
add_archive "$apt_archive"
(cd "$release" && sha256sum -c SHA256SUMS.download)
du -h "$release/"*
