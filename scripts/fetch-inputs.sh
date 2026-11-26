#!/usr/bin/env bash
set -euo pipefail

repo=$(cd -- "$(dirname -- "$0")/.." && pwd)
mode=${1:-download}
[[ $mode == download || $mode == --verify-only || $mode == --cosmic-only ]]
mkdir -p "$repo/inputs/debs"
exec 9>"$repo/inputs/.downloads.lock"
flock 9

check_sha256() {
    printf '%s  %s\n' "$2" "$1" | sha256sum -c -
}

fetch() {
    local url=$1 file=$2 digest=$3
    [[ $digest =~ ^[[:xdigit:]]{64}$ ]]
    if [[ -f $file ]] && check_sha256 "$file" "$digest" >/dev/null 2>&1; then
        printf 'Verified %s\n' "$(basename "$file")"
        return
    fi
    if [[ $mode == --verify-only ]]; then
        printf 'Missing file or SHA-256 mismatch: %s\n' "$file" >&2
        return 1
    fi
    [[ $url == https://* ]]
    printf 'Downloading %s\n' "$(basename "$file")"
    curl --fail --location --show-error --silent --proto '=https' --proto-redir '=https' \
        --retry 3 --retry-connrefused --connect-timeout 20 --max-time 1800 \
        --output "$file.partial" "$url"
    check_sha256 "$file.partial" "$digest"
    mv -f -- "$file.partial" "$file"
}

while IFS=$'\t' read -r name digest revision source; do
    [[ $name != input ]] || continue
    [[ $mode != --cosmic-only || $name == cosmic-settings.tar.gz ]] || continue
    [[ $name =~ ^[a-zA-Z0-9._+-]+$ ]]
    if [[ $name == *.iso ]]; then
        if [[ -n ${SHENG_POP_ISO:-} ]]; then
            check_sha256 "$SHENG_POP_ISO" "$digest"
        elif [[ -f $repo/../$name ]]; then
            check_sha256 "$repo/../$name" "$digest"
        else
            fetch "${SHENG_POP_ISO_URL:-$source}" "$repo/inputs/$name" "$digest"
        fi
    else
        if [[ ! $revision =~ ^[[:xdigit:]]{40}$ ]]; then
            printf 'Invalid pinned Git commit for %s: %s\n' "$name" "$revision" >&2
            exit 1
        fi
        [[ $source =~ ^https://github[.]com/([a-zA-Z0-9._-]+)/([a-zA-Z0-9._-]+)(/|$) ]]
        fetch "https://codeload.github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/tar.gz/$revision" \
            "$repo/inputs/$name" "$digest"
    fi
done < "$repo/sources.tsv"

if [[ $mode == --cosmic-only ]]; then exit 0; fi

while IFS=$'\t' read -r asset digest url; do
    [[ $asset != asset ]] || continue
    [[ $asset =~ ^[a-zA-Z0-9._+-]+[.]deb$ ]]
    fetch "$url" "$repo/inputs/debs/$asset" "$digest"
done < "$repo/device-sources.tsv"
