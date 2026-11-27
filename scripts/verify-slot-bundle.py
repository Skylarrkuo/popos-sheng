#!/usr/bin/env python3
"""Validate an explicitly supplied tablet's calibration before embedding it."""

import argparse
import hashlib
import re
from pathlib import Path


LABELS = (
    "xbl", "xbl_config", "abl", "devcfg", "uefi", "boot", "init_boot",
    "vendor_boot", "dtbo", "vbmeta", "vbmeta_system",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("boot_image", type=Path)
    args = parser.parse_args()

    with (args.bundle / "qbootctl-sheng").open("rb") as executable:
        header = executable.read(20)
    if header[:6] != b"\x7fELF\x02\x01" or header[18:20] != b"\xb7\x00":
        raise SystemExit("qbootctl-sheng must be an ARM64 Linux executable")

    expected_labels = {f"{name}_{slot}" for name in LABELS for slot in ("a", "b")}
    manifest = (args.bundle / "boot.sha256").read_text(encoding="ascii")
    for line in manifest.splitlines():
        entry = re.fullmatch(r"[0-9a-f]{64}  /dev/disk/by-partlabel/([a-z_]+)", line)
        if entry is None or entry[1] not in expected_labels:
            raise SystemExit("Invalid or duplicate calibrated partition")
        expected_labels.remove(entry[1])
    if expected_labels:
        raise SystemExit("The calibration is missing boot partition hashes")

    record = (args.bundle / "boot-b-image.sha256").read_text(encoding="ascii")
    match = re.fullmatch(r"([0-9a-f]{64})[ \t]+([0-9]+)\n?", record)
    with args.boot_image.open("rb") as image:
        digest = hashlib.file_digest(image, "sha256").hexdigest()
    if match is None or match[1] != digest or int(match[2]) != args.boot_image.stat().st_size:
        raise SystemExit("The built B-slot boot image differs from the calibrated tablet")


if __name__ == "__main__":
    main()
