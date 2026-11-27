#!/usr/bin/env bash
set -euo pipefail

if (($# != 3)); then
    echo "Usage: $0 QBOOTCTL_CHECKOUT PROFILE_HEADER OUTPUT_BINARY" >&2
    exit 2
fi
repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
checkout=$(cd -- "$1" && pwd -P)
upstream=39a6e6daaf029fb0a083777679a15ea2c18f72de
stage=$(mktemp -d)
trap 'rm -r -- "$stage"' EXIT

git -c safe.directory="$checkout" -C "$checkout" archive "$upstream" | tar -x -C "$stage"
patch -d "$stage" -p1 --fuzz=0 < "$repo/patches/qbootctl-sheng.patch"
install -m 0644 "$2" "$stage/sheng-profile-data.h"

compiler=cc
if [[ $(uname -m) != aarch64 ]]; then compiler=aarch64-linux-gnu-gcc; fi
"${SHENG_POP_ARM64_CC:-$compiler}" -std=gnu11 -O2 -Wall -Wextra -Werror -static \
    -I "$stage" '-DQBOOTCTL_SHENG_PROFILE="sheng-profile-data.h"' \
    "$stage/"{qbootctl,bootctrl_impl,gpt-utils,ufs-bsg,crc32}.c -o "$stage/qbootctl-sheng"
install -Dm0755 "$stage/qbootctl-sheng" "$3"
