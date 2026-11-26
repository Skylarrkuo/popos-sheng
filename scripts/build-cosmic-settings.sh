#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
archive=$repo/inputs/cosmic-settings.tar.gz
patch=$repo/patches/cosmic-settings-sheng-about.patch
work=${SHENG_POP_COSMIC_WORK:-/var/tmp}
pool=$repo/apt-local/pool
version=1.11.0~1795220432~26.04~ee6ea8a+sheng1
name=cosmic-settings_${version}_arm64.deb
mkdir -p "$pool"

digest=$(awk -F '\t' '$1 == "cosmic-settings.tar.gz" {print $2}' "$repo/sources.tsv")
printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -

if [[ -n ${SHENG_POP_COSMIC_DEB:-} ]]; then
    if [[ -n ${SHENG_POP_COSMIC_DEB_SHA256:-} ]]; then
        [[ $SHENG_POP_COSMIC_DEB_SHA256 =~ ^[[:xdigit:]]{64}$ ]]
        printf '%s  %s\n' "$SHENG_POP_COSMIC_DEB_SHA256" "$SHENG_POP_COSMIC_DEB" | sha256sum -c -
    else
        # The ARM64 package previously built and tested on Sheng used this exact patch.
        printf '%s  %s\n' \
            74af7380da70e2cbf57e0beb4ade800973ed5e9af41ecc73137d750a33582ab9 "$patch" \
            1e58e1e0f849c2ab1bfb1fb27546f613668fd13f1af3b84d91538ceaf97dea89 "$SHENG_POP_COSMIC_DEB" \
            | sha256sum -c -
    fi
    deb=$SHENG_POP_COSMIC_DEB
else
    if [[ $(dpkg --print-architecture) != arm64 ]]; then
        echo 'Build COSMIC Settings on an ARM64 Ubuntu host or supply the verified local package via SHENG_POP_COSMIC_DEB.' >&2
        exit 1
    fi
    stage=$(mktemp -d "$work/popos-sheng-cosmic.XXXXXXXX")
    trap 'rm -r -- "$stage"' EXIT
    mkdir "$stage/source"
    tar -xzf "$archive" --strip-components=1 --no-same-owner -C "$stage/source"
    cd "$stage/source"
    patch -p1 --fuzz=0 < "$patch"
    export DEBFULLNAME='Pop!_OS Sheng build'
    export DEBEMAIL=local@sheng.invalid
    dch --newversion "$version" --force-bad-version --distribution resolute --force-distribution \
        'Report Xiaomi Pad 6S Pro hardware in COSMIC Settings.'
    sed -i 's/just build-release --features pop-os/just build-release --locked --features pop-os/' debian/rules
    export CARGO_BUILD_JOBS=${SHENG_POP_CARGO_JOBS:-4}
    export CARGO_INCREMENTAL=0
    export CARGO_NET_GIT_FETCH_WITH_CLI=true
    export DEB_BUILD_OPTIONS=noautodbgsym
    # rust-all is satisfied by the upstream, pinned Rust toolchain in the checkout.
    dpkg-buildpackage -b -us -uc -d -nc
    deb=$stage/$name
fi

[[ $(dpkg-deb -f "$deb" Package) == cosmic-settings ]]
[[ $(dpkg-deb -f "$deb" Version) == "$version" ]]
[[ $(dpkg-deb -f "$deb" Architecture) == arm64 ]]
install -m 0644 "$deb" "$pool/$name.partial"
mv -f -- "$pool/$name.partial" "$pool/$name"
echo "Prepared $name"
sha256sum "$pool/$name"
