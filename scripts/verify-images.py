#!/usr/bin/env python3
"""Check the stock-ABL boot payload and the Android sparse root geometry."""

import argparse
import gzip
from pathlib import Path
import struct


def verify_boot(output: Path) -> None:
    boot = (output / "boot-popos-sheng-dual.img").read_bytes()
    assert boot[:8] == b"ANDROID!", "Android boot magic"
    kernel_size, kernel_address, ramdisk_size, _, second_size, _, tags, page, version = (
        struct.unpack_from("<9I", boot, 8)
    )
    assert (kernel_address, tags, page, version) == (0x8000, 0x1E00000, 4096, 0)
    assert ramdisk_size == second_size == 0
    assert boot[64:576].split(b"\0", 1)[0] == (
        b"root=PARTLABEL=linux rootwait rw fsck.repair=yes"
    )
    image = output / "kernel" / "Image.gz"
    dtb = (output / "kernel" / "sm8550-xiaomi-sheng.dtb").read_bytes()
    assert dtb[:4] == b"\xd0\x0d\xfe\xed"
    kernel = image.read_bytes() + dtb
    assert boot[page : page + kernel_size] == kernel
    assert len(boot) == page + ((kernel_size + page - 1) // page) * page
    with gzip.open(image, "rb") as stream:
        assert stream.read(60)[56:60] == b"ARM\x64", "ARM64 Image magic"
    print(f"Boot: {len(boot)} bytes, ARM64 Image.gz and Sheng DTB, Android v0")


def verify_root(output: Path) -> None:
    path = output / "rootfs-popos-26.04-cosmic-sheng-linux.img"
    with path.open("rb") as stream:
        magic, major, _, header, chunk, block, blocks, total_chunks, _ = struct.unpack(
            "<I4H4I", stream.read(28)
        )
        assert (magic, major, header, chunk, block) == (0xED26FF3A, 1, 28, 12, 4096)
        expanded_blocks = 0
        for _ in range(total_chunks):
            kind, _, count, size = struct.unpack("<2H2I", stream.read(chunk))
            payload = {0xCAC1: count * block, 0xCAC2: 4, 0xCAC3: 0, 0xCAC4: 4}[kind]
            assert size == chunk + payload
            stream.seek(payload, 1)
            expanded_blocks += count
        assert stream.tell() == path.stat().st_size and blocks == expanded_blocks
        assert blocks * block == 20 * 1024**3
    print(f"Rootfs: {path.stat().st_size} bytes, {blocks * block} bytes expanded")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--boot-only", action="store_true")
    args = parser.parse_args()
    verify_boot(args.output)
    if not args.boot_only:
        verify_root(args.output)


if __name__ == "__main__":
    main()
