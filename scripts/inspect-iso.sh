#!/usr/bin/env bash
set -euo pipefail

iso=$(realpath "$1")
mount_dir=$(mktemp -d /tmp/pop-sheng-iso.XXXXXXXX)
trap 'if mountpoint -q "$mount_dir"; then umount "$mount_dir"; fi; rmdir "$mount_dir"' EXIT
mount -o ro,loop "$iso" "$mount_dir"
find "$mount_dir" -maxdepth 3 -type f -printf '%P\t%s\n' | sort
while IFS= read -r -d '' squashfs; do
    printf '\nSquashFS metadata for %s\n' "${squashfs#"$mount_dir"/}"
    unsquashfs -s "$squashfs"
    for file in etc/os-release etc/greetd/config.toml etc/fstab; do
        printf '\n%s\n' "$file"
        unsquashfs -cat "$squashfs" "$file" 2>/dev/null || :
    done
done < <(find "$mount_dir" -type f -name '*.squashfs' -print0)
