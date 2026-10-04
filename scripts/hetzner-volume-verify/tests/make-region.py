#!/usr/bin/env python3
"""Write one Anvil region file for the check-world tests.

usage: make-region.py PATH X,Z:KIND [X,Z:KIND ...]

KIND is zlib, gzip, lz4 or none (a valid chunk), or a corrupt variant:
truncated (zlib stream cut short), outside (location entry past end of
file), badcomp (unknown compression type), badnbt (valid zlib, not NBT).
"""
import gzip
import struct
import sys
import zlib
from pathlib import Path

import lz4.block

SECTOR = 4096


def nbt_string(s: str) -> bytes:
    raw = s.encode()
    return struct.pack(">H", len(raw)) + raw


def valid_nbt(seed: int, pad: int = 0) -> bytes:
    body = b"\x0a" + nbt_string("")
    body += b"\x03" + nbt_string("DataVersion") + struct.pack(">i", 3955)
    body += b"\x08" + nbt_string("Status") + nbt_string("minecraft:full")
    body += b"\x04" + nbt_string("InhabitedTime") + struct.pack(">q", seed)
    body += b"\x0c" + nbt_string("Heightmaps") + struct.pack(">i", 2) + struct.pack(">qq", 1, 2)
    body += b"\x09" + nbt_string("sections") + b"\x0a" + struct.pack(">i", 2)
    body += b"\x01" + nbt_string("Y") + b"\xff" + b"\x00"
    body += b"\x07" + nbt_string("data") + struct.pack(">i", 3) + b"abc" + b"\x00"
    if pad:
        body += b"\x07" + nbt_string("pad") + struct.pack(">i", pad) + bytes(pad)
    return body + b"\x00"


def record(ctype: int, payload: bytes) -> bytes:
    raw = struct.pack(">IB", len(payload) + 1, ctype) + payload
    return raw + bytes(-len(raw) % SECTOR)


def encode(kind: str, seed: int) -> tuple[int, bytes]:
    nbt = valid_nbt(seed)
    if kind == "zlib":
        return 2, zlib.compress(nbt)
    if kind == "gzip":
        return 1, gzip.compress(nbt)
    if kind == "lz4":
        return 4, lz4.block.compress(nbt, store_size=False)
    if kind == "none":
        return 3, nbt
    if kind == "truncated":
        full = zlib.compress(valid_nbt(seed, pad=2048))
        return 2, full[: len(full) // 2]
    if kind == "badcomp":
        return 9, zlib.compress(nbt)
    if kind == "badnbt":
        return 2, zlib.compress(b"\x01\x00\x00not a compound")
    raise SystemExit(f"make-region: unknown chunk kind {kind!r}")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    path = Path(argv[1])
    locations = bytearray(SECTOR)
    body = bytearray()
    sector = 2
    for i, spec in enumerate(argv[2:]):
        coords, _, kind = spec.partition(":")
        x, z = (int(v) for v in coords.split(","))
        slot = 4 * ((x & 31) + (z & 31) * 32)
        if kind == "outside":
            locations[slot : slot + 4] = struct.pack(">I", (900 << 8) | 1)
            continue
        ctype, payload = encode(kind, i)
        rec = record(ctype, payload)
        count = len(rec) // SECTOR
        locations[slot : slot + 4] = struct.pack(">I", (sector << 8) | count)
        body += rec
        sector += count
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(locations) + bytes(SECTOR) + bytes(body))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
