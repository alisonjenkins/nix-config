#!/usr/bin/env python3
"""Check that every chunk in a Minecraft world's Anvil region files is readable.

Do not run this directly; check-world.sh validates the arguments and calls it.
Read-only: files are opened for reading only.
"""
from __future__ import annotations

import os
import struct
import sys
import zlib
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
import re
import shlex

import lz4.block
import lz4.frame

SECTOR = 4096
HEADER = 2 * SECTOR
GZIP, ZLIB, NONE, LZ4 = 1, 2, 3, 4
LZ4_BLOCK_MAGIC = b"LZ4Block"
LZ4_BLOCK_HEADER = 21
LZ4_FRAME_MAGIC = b"\x04\x22\x4d\x18"
REGION_NAME = re.compile(r"^r\.(-?\d+)\.(-?\d+)\.mca$")
FIXED_SIZE = {1: 1, 2: 2, 3: 4, 4: 8, 5: 4, 6: 8}
ARRAY_ELEMENT = {7: 1, 11: 4, 12: 8}
TAG_STRING, TAG_LIST, TAG_COMPOUND = 8, 9, 10


class ChunkError(Exception):
    """A chunk is unreadable; the message is the short reason."""


@dataclass(frozen=True)
class Bad:
    x: int
    z: int
    reason: str


@dataclass(frozen=True)
class FileResult:
    path: str
    read: int
    bad: tuple[Bad, ...]
    file_reason: str = ""


def walk_nbt(data: bytes) -> None:
    """Raise ChunkError unless data is one well-formed NBT root compound.

    Iterative so nesting depth cannot overflow the interpreter stack.
    """
    size = len(data)
    if size < 3 or data[0] != TAG_COMPOUND:
        raise ChunkError("bad-nbt root is not a compound")
    pos = 3 + struct.unpack_from(">H", data, 1)[0]
    # Each frame is [remaining, element_type]: remaining < 0 means a compound.
    stack: list[list[int]] = [[-1, 0]]
    unpack = struct.unpack_from
    try:
        while stack:
            frame = stack[-1]
            if frame[0] < 0:
                tag = data[pos]
                pos += 1
                if tag == 0:
                    stack.pop()
                    continue
                if tag > 12:
                    raise ChunkError(f"bad-nbt unknown tag {tag}")
                pos += 2 + unpack(">H", data, pos)[0]
            else:
                if frame[0] == 0:
                    stack.pop()
                    continue
                frame[0] -= 1
                tag = frame[1]
            if tag in FIXED_SIZE:
                pos += FIXED_SIZE[tag]
            elif tag in ARRAY_ELEMENT:
                length = unpack(">i", data, pos)[0]
                if length < 0:
                    raise ChunkError("bad-nbt negative array length")
                pos += 4 + length * ARRAY_ELEMENT[tag]
            elif tag == TAG_STRING:
                pos += 2 + unpack(">H", data, pos)[0]
            elif tag == TAG_LIST:
                etype = data[pos]
                count = unpack(">i", data, pos + 1)[0]
                pos += 5
                if count < 0 or etype > 12 or (etype == 0 and count > 0):
                    raise ChunkError("bad-nbt invalid list header")
                if etype in FIXED_SIZE:
                    pos += count * FIXED_SIZE[etype]
                elif count > 0:
                    stack.append([count, etype])
            elif tag == TAG_COMPOUND:
                stack.append([-1, 0])
            else:
                raise ChunkError(f"bad-nbt unexpected tag {tag}")
            if pos > size:
                raise ChunkError("bad-nbt data runs past end")
    except (IndexError, struct.error):
        raise ChunkError("bad-nbt data runs past end") from None


def inflate(decoder: "zlib._Decompress", payload: bytes) -> bytes:
    try:
        out = decoder.decompress(payload)
    except zlib.error as exc:
        raise ChunkError(f"decompress-failed {exc}") from None
    if not decoder.eof:
        raise ChunkError("decompress-failed stream is truncated")
    return out


def lz4_decode(payload: bytes) -> bytes:
    if payload.startswith(LZ4_FRAME_MAGIC):
        try:
            return lz4.frame.decompress(payload)
        except RuntimeError as exc:
            raise ChunkError(f"decompress-failed lz4 {exc}") from None
    if not payload.startswith(LZ4_BLOCK_MAGIC):
        raise ChunkError("decompress-failed lz4 stream has no known magic")
    out = bytearray()
    pos = 0
    while True:
        if pos + LZ4_BLOCK_HEADER > len(payload) or payload[pos : pos + 8] != LZ4_BLOCK_MAGIC:
            raise ChunkError("decompress-failed lz4 stream is truncated")
        token = payload[pos + 8]
        clen, dlen = struct.unpack_from("<ii", payload, pos + 9)
        pos += LZ4_BLOCK_HEADER
        if dlen == 0:
            return bytes(out)
        if clen < 0 or dlen < 0 or pos + clen > len(payload):
            raise ChunkError("decompress-failed lz4 block runs past end")
        block = payload[pos : pos + clen]
        pos += clen
        if token & 0xF0 == 0x10:
            if clen != dlen:
                raise ChunkError("decompress-failed lz4 stored block size mismatch")
            out += block
        elif token & 0xF0 == 0x20:
            try:
                out += lz4.block.decompress(block, uncompressed_size=dlen)
            except lz4.block.LZ4BlockError as exc:
                raise ChunkError(f"decompress-failed lz4 {exc}") from None
        else:
            raise ChunkError("decompress-failed lz4 unknown block method")


def decode_chunk(data: bytes, offset: int, sectors: int) -> bytes:
    start = offset * SECTOR
    if offset < 2 or start + 5 > len(data):
        raise ChunkError("outside-file location entry points past the file")
    length, ctype = struct.unpack_from(">IB", data, start)
    if length < 1:
        raise ChunkError("bad-length chunk length is zero")
    if start + 4 + length > len(data):
        raise ChunkError("outside-file chunk data runs past the file")
    if 4 + length > sectors * SECTOR:
        raise ChunkError("bad-length chunk is larger than its sectors")
    payload = data[start + 5 : start + 4 + length]
    if ctype == ZLIB:
        return inflate(zlib.decompressobj(), payload)
    if ctype == GZIP:
        return inflate(zlib.decompressobj(31), payload)
    if ctype == NONE:
        return payload
    if ctype == LZ4:
        return lz4_decode(payload)
    raise ChunkError(f"bad-compression-type {ctype}")


def check_file(path: str) -> FileResult:
    with open(path, "rb") as handle:
        data = handle.read()
    if not data:
        return FileResult(path, 0, ())
    if len(data) < HEADER:
        return FileResult(path, 0, (), "header-truncated file is shorter than the 8192-byte header")
    bad: list[Bad] = []
    read = 0
    for index in range(1024):
        (entry,) = struct.unpack_from(">I", data, index * 4)
        if entry == 0:
            continue
        x, z = index % 32, index // 32
        try:
            walk_nbt(decode_chunk(data, entry >> 8, entry & 0xFF))
            read += 1
        except ChunkError as exc:
            bad.append(Bad(x, z, str(exc).replace(" ", ":", 1).replace(" ", "_")))
    return FileResult(path, read, tuple(bad))


def region_files(world: Path) -> tuple[list[str], int]:
    """Return (.mca files under every region dir, number of region dirs)."""
    files: list[str] = []
    region_dirs = 0
    for root, dirs, names in os.walk(world):
        if os.path.basename(root) == "region":
            region_dirs += 1
            files.extend(os.path.join(root, n) for n in names if n.endswith(".mca"))
    files.sort()
    return files, region_dirs


def timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv: list[str]) -> int:
    world = Path(argv[1])
    files, region_dirs = region_files(world)
    if region_dirs == 0:
        print(f"{timestamp()} check-world: no region directory under {world}", file=sys.stderr)
        return 1
    if not files:
        print(f"{timestamp()} check-world: no .mca file in any region directory under {world}", file=sys.stderr)
        return 1
    jobs = int(os.environ.get("CHECK_WORLD_JOBS", "0")) or os.cpu_count() or 1
    chunks_read = 0
    unreadable = 0
    with ProcessPoolExecutor(max_workers=jobs) as pool:
        for result in pool.map(check_file, files, chunksize=4):
            chunks_read += result.read
            quoted = shlex.quote(result.path)
            if result.file_reason:
                unreadable += 1
                print(f"unreadable file={quoted} chunk=- reason={result.file_reason.replace(' ', '_')}")
            match = REGION_NAME.match(os.path.basename(result.path))
            for item in result.bad:
                unreadable += 1
                line = f"unreadable file={quoted} chunk={item.x},{item.z} reason={item.reason}"
                if match:
                    ax = int(match.group(1)) * 32 + item.x
                    az = int(match.group(2)) * 32 + item.z
                    line += f" abs={ax},{az}"
                print(line)
    print(f"{timestamp()} chunks_read={chunks_read} unreadable={unreadable} files={len(files)}")
    return 0 if unreadable == 0 and chunks_read > 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
