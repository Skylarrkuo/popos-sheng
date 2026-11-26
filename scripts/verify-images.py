#!/usr/bin/env python3
"""Check the stock-ABL boot payload and the Android sparse root geometry."""

import argparse
from contextlib import nullcontext
import gzip
from pathlib import Path
import struct
import sys


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


def read_exact(stream, size: int) -> bytes:
    data = stream.read(size)
    assert len(data) == size, "Truncated image"
    return data


def compare_chunk(sparse, raw, kind: int, size: int) -> None:
    if kind == 0xCAC4:  # CRC32 carries no expanded blocks.
        read_exact(sparse, 4)
        return

    pattern = None
    if kind == 0xCAC2:
        pattern = read_exact(sparse, 4)
    elif kind == 0xCAC3:
        pattern = b"\0"
    buffer_size = 1024 * 1024
    repeated = pattern * (buffer_size // len(pattern)) if pattern else None
    while size:
        count = min(size, buffer_size)
        expanded = read_exact(sparse, count) if repeated is None else repeated[:count]
        assert expanded == read_exact(raw, count), "Sparse image differs from source ext4"
        size -= count


def verify_root(output: Path, root_input: str | None, raw_path: Path | None) -> None:
    if root_input == "-":
        assert raw_path is not None, "Streaming verification requires the source ext4"
        sparse_context = nullcontext(sys.stdin.buffer)
    else:
        path = Path(root_input) if root_input else output / "rootfs-popos-26.04-cosmic-sheng-linux.img"
        sparse_context = path.open("rb")
    raw_context = raw_path.open("rb") if raw_path else nullcontext(None)
    with sparse_context as stream, raw_context as raw:
        magic, major, _, header, chunk, block, blocks, total_chunks, _ = struct.unpack(
            "<I4H4I", read_exact(stream, 28)
        )
        assert (magic, major, header, chunk, block) == (0xED26FF3A, 1, 28, 12, 4096)
        assert blocks * block == 20 * 1024**3
        expanded_blocks = 0
        sparse_size = header
        for _ in range(total_chunks):
            kind, _, count, size = struct.unpack("<2H2I", read_exact(stream, chunk))
            payload = {0xCAC1: count * block, 0xCAC2: 4, 0xCAC3: 0, 0xCAC4: 4}[kind]
            assert size == chunk + payload
            assert kind != 0xCAC4 or count == 0
            expanded_blocks += count
            assert expanded_blocks <= blocks
            sparse_size += size
            if raw is None:
                stream.seek(payload, 1)
            else:
                compare_chunk(stream, raw, kind, count * block)
        assert blocks == expanded_blocks and stream.read(1) == b""
        if raw is None:
            assert stream.tell() == path.stat().st_size
        else:
            assert raw.read(1) == b"", "Source ext4 has trailing data"
    print(f"Rootfs: {sparse_size} bytes, {blocks * block} bytes expanded")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--boot-only", action="store_true")
    parser.add_argument("--sparse", help="Sparse image path or - for standard input")
    parser.add_argument("--raw-rootfs", type=Path, help="Compare expanded bytes with this ext4 image")
    args = parser.parse_args()
    verify_boot(args.output)
    if not args.boot_only:
        verify_root(args.output, args.sparse, args.raw_rootfs)


if __name__ == "__main__":
    main()
