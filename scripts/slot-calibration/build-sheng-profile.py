#!/usr/bin/env python3
"""Generate a device-bound C profile from GPT captures made on Sheng."""

import argparse
import base64
import hashlib
import json
import runpy
from pathlib import Path


PROBES = {
    "sda": "linux",
    "sdb": "xbl_a",
    "sdc": "xbl_b",
    "sdd": "cdt",
    "sdf": "modemst1",
    "sde": "boot_a",
}
ACTIVE_OR_UNBOOTABLE = 0x84


def c_array(data, indent):
    return "\n".join(
        indent + '"' + "".join(f"\\x{x:02x}" for x in data[i:i + 32]) + '"'
        for i in range(0, len(data), 32)
    )


def check_partition_changes(check, first_disks, first, other_disks, other):
    check(first_disks == other_disks and first.keys() == other.keys(),
          "Captures do not describe the same disk layout")
    for label, (disk, offset, entry) in first.items():
        other_disk, other_offset, other_entry = other[label]
        check((disk, offset) == (other_disk, other_offset), f"Partition moved: {label}")
        check(entry[16:54] == other_entry[16:54] and entry[55:] == other_entry[55:],
              f"Unrelated GPT fields changed: {label}")
        if entry != other_entry:
            check(label.endswith(("_a", "_b")), f"Unslotted partition changed: {label}")
        if entry[:16] != other_entry[:16]:
            peer = label[:-1] + ("b" if label.endswith("_a") else "a")
            check(peer in first and entry[:16] == other[peer][2][:16]
                  and other_entry[:16] == first[peer][2][:16],
                  f"Not a GUID exchange between slots: {label}")


def same_header_layout(first, other):
    return first[:16] == other[:16] and first[20:88] == other[20:88] and first[92:] == other[92:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot-a", required=True, type=Path)
    parser.add_argument("--slot-b", required=True, type=Path)
    parser.add_argument("--slot-b-alternate", type=Path,
                        help="Additional verified capture with slot B active")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    audit = runpy.run_path(str(Path(__file__).with_name("audit-sheng.py")))
    check, load = audit["check"], audit["load"]
    ga, pa = load(args.slot_a, "a")
    gb, pb = load(args.slot_b, "b")
    check_partition_changes(check, ga, pa, gb, pb)

    sources = [p.read_bytes() for p in (args.slot_a, args.slot_b)]
    tables_a, tables_b = (json.loads(src)["tables"] for src in sources)
    check(tables_a.keys() == tables_b.keys() == PROBES.keys(), "Unexpected Sheng LUN inventory")
    alternate_by_id = {}
    alternate_pairs = {}
    if args.slot_b_alternate:
        disks, parts = load(args.slot_b_alternate, "b")
        check_partition_changes(check, gb, pb, disks, parts)
        for label, (disk_id, offset, entry) in pb.items():
            alternate_entry = parts[label][2]
            check(not ((entry[54] ^ alternate_entry[54]) & ACTIVE_OR_UNBOOTABLE),
                  f"Alternate capture changes active or unbootable flags: {label}")
            if label.endswith("_a") and entry[:16] != alternate_entry[:16]:
                peer_disk_id, peer_offset, _ = pb[label[:-1] + "b"]
                check(disk_id == peer_disk_id, f"Alternate GUID pair spans LUNs: {label}")
                alternate_pairs.setdefault(disk_id, []).append((offset, peer_offset))
        sources.append(args.slot_b_alternate.read_bytes())
        # The same UFS LUN can appear under a different /dev/sdX name across boots.
        alternate_by_id = {
            base64.b64decode(table["p_header"])[56:72]: table
            for table in json.loads(sources[-1])["tables"].values()
        }
    content = [
        "/* Generated from verified, same-device A/B slot captures. */",
        *[f"/* {slot} capture SHA-256: {hashlib.sha256(src).hexdigest()} */"
          for slot, src in zip(("A", "B", "B alternate"), sources)],
        "static const struct sheng_reference sheng_profile[] = {",
    ]
    for disk, label in PROBES.items():
        a, b = tables_a[disk], tables_b[disk]
        first_a, first_b = (base64.b64decode(t["p_header"]) for t in (a, b))
        disk_id = first_a[56:72]
        check(pa[label][0] == pb[label][0] == disk_id, f"{disk}: probe is on another LUN")
        check(same_header_layout(first_a, first_b), f"{disk}: unrelated primary header fields changed")
        backup_a, backup_b = (base64.b64decode(t["b_header"]) for t in (a, b))
        check(same_header_layout(backup_a, backup_b), f"{disk}: unrelated backup header fields changed")
        size = a["entry"] * a["count"]
        content.extend([
            "\t{",
            f'\t\t.probe = "{label}",',
            f"\t\t.block_size = {a['block']}, .entry_size = {a['entry']}, .table_size = {size},",
            "\t\t.primary_header =",
            c_array(first_a, "\t\t\t") + ",",
            "\t\t.backup_header =",
            c_array(backup_a, "\t\t\t") + ",",
            "\t\t.entries = {",
            *[c_array(base64.b64decode(t["p_entries"])[:size], "\t\t\t") + "," for t in (a, b)],
            "\t\t},",
        ])
        if alternate_by_id:
            alternate = alternate_by_id[disk_id]
            check(same_header_layout(first_b, base64.b64decode(alternate["p_header"])),
                  f"{disk}: unrelated alternate primary header fields changed")
            check(same_header_layout(backup_b, base64.b64decode(alternate["b_header"])),
                  f"{disk}: unrelated alternate backup header fields changed")
            content.extend([
                "\t\t.alternate_b_entries =",
                c_array(base64.b64decode(alternate["p_entries"])[:size], "\t\t\t") + ",",
            ])
            pairs = alternate_pairs.get(disk_id)
            if pairs:
                content.extend([
                    "\t\t.alternate_b_guid_pairs = (const struct sheng_guid_pair[]) {",
                    *[f"\t\t\t{{ {a}, {b} }}," for a, b in pairs],
                    "\t\t},",
                    f"\t\t.alternate_b_guid_pair_count = {len(pairs)},",
                ])
        content.append("\t},")
    content.append("};")
    args.output.write_text("\n".join(content) + "\n", encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
