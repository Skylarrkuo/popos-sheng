#!/usr/bin/env python3
"""Compare captured Sheng GPTs. This program only reads JSON files."""

import argparse
import base64
import json
import struct
import uuid
import zlib
from pathlib import Path


GENERIC = uuid.UUID("77036cd4-03d5-42bb-8ed1-37e5a88baa34").bytes_le
UPSTREAM = set(
    "abl aop apdp cmnlib cmnlib64 devcfg dtbo hyp keymaster msadp qupfw "
    "storsec tz vbmeta vbmeta_system boot system vendor modem system_ext product".split()
)


def check(condition, message):
    if not condition:
        raise ValueError(message)


def get_copy(table, prefix, area, other):
    header = base64.b64decode(table[f"{prefix}_header"], validate=True)
    entries = base64.b64decode(table[f"{prefix}_entries"], validate=True)
    block = table["block"]
    check(len(header) == block and header[:8] == b"EFI PART", "Invalid GPT header")
    size, crc = struct.unpack_from("<II", header, 12)
    check(92 <= size <= block, "Incorrect GPT header size")
    check(zlib.crc32(header[:16] + bytes(4) + header[20:size]) == crc, "Invalid header CRC")
    current, alternate, start, end, disk_id, lba, count, entry, crc = struct.unpack_from(
        "<QQQQ16sQIII", header, 24
    )
    check((current, alternate) == (area, other), "Incorrect GPT header location")
    check((lba, count, entry) == (table[f"{prefix}_table"], table["count"], table["entry"]),
          "GPT geometry does not match capture")
    check(count > 0 and entry >= 128 and entry % 128 == 0 and count * entry <= len(entries),
          "Invalid GPT entry array")
    data = entries[:count * entry]
    check(zlib.crc32(data) == crc, "Invalid partition CRC")
    return (disk_id, start, end, entry, data)


def load(path, expected_slot):
    try:
        capture = json.loads(path.read_text(encoding="utf-8"))
        check(capture["boot_lun"] == {"a": 1, "b": 2}[expected_slot], "Unexpected boot LUN")
        disks, partitions = {}, {}
        for table in capture["tables"].values():
            primary = get_copy(table, "p", 1, table["last"])
            backup = get_copy(table, "b", table["last"], 1)
            check(primary == backup, "GPT copies disagree")
            disk_id, start, end, width, data = primary
            check(disk_id not in disks, "Duplicate GPT disk identity")
            disks[disk_id] = (table["block"], table["last"], start, end, width)
            for offset in range(0, len(data), width):
                entry = data[offset:offset + width]
                if entry[:16] == bytes(16):
                    continue
                name = entry[56:128].decode("utf-16le").rstrip("\0")
                check(name not in partitions, f"Duplicate partition {name!r}")
                partitions[name] = (disk_id, offset, entry)
        active = [s for s in ("a", "b") if partitions[f"boot_{s}"][2][54] & 4]
        check(active == [expected_slot], "GPT boot flags and UFS boot LUN disagree")
        check("linux" in partitions and "vendor_boot_a" in partitions, "Not a Sheng dual-boot capture")
    except (KeyError, TypeError, ValueError, struct.error, OSError) as exc:
        raise ValueError(f"{path}: {exc}") from exc
    return disks, partitions


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot-b", required=True, type=Path)
    parser.add_argument("--slot-a", type=Path)
    args = parser.parse_args()
    disks_b, slot_b = load(args.slot_b, "b")
    omitted = []
    for a in sorted(name for name in slot_b if name.endswith("_a")):
        b = a[:-1] + "b"
        if b not in slot_b or a[:-2] in UPSTREAM:
            continue
        ea, eb = slot_b[a][2], slot_b[b][2]
        if ea[:16] == GENERIC and eb[:16] != GENERIC and eb[54] & 4:
            omitted.append(a[:-2])
    print(f"B-slot capture: {len(disks_b)} matching GPT pairs, boot LUN 2")
    print(f"Active-B GUID pairs missing from the upstream list ({len(omitted)}): "
          + ", ".join(omitted))
    if args.slot_a is None:
        print("Comparison incomplete: a same-device A-slot capture was not supplied.")
        return

    disks_a, slot_a = load(args.slot_a, "a")
    check(disks_a == disks_b and slot_a.keys() == slot_b.keys(), "Captures have different layouts")
    count = 0
    for name in sorted(slot_a):
        da, oa, ea = slot_a[name]
        db, ob, eb = slot_b[name]
        check(da == db and oa == ob and ea[16:54] == eb[16:54] and ea[55:] == eb[55:],
              f"Unexpected GPT change in {name!r} outside the type GUID or slot byte")
        if ea == eb:
            continue
        check(name.endswith(("_a", "_b")), f"Unexpected change to unslotted partition {name!r}")
        print(f"{name}: GUID {'changed' if ea[:16] != eb[:16] else 'unchanged'}, "
              f"slot flags {eb[54]:02x} -> {ea[54]:02x}")
        count += 1
    print(f"Same-device comparison: {count} entries changed; no writes performed.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(str(error)) from error
