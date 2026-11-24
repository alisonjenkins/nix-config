"""Write a Minecraft servers.dat (uncompressed NBT) with one entry.

Usage: servers-dat.py <name> <address> <output>
"""
import struct
import sys

TAG_END, TAG_STRING, TAG_LIST, TAG_COMPOUND = 0, 8, 9, 10


def nbt_string(value):
    data = value.encode("utf-8")
    return struct.pack(">H", len(data)) + data


def named(tag, name):
    return struct.pack(">b", tag) + nbt_string(name)


def servers_dat(name, address):
    server = (
        named(TAG_STRING, "ip") + nbt_string(address)
        + named(TAG_STRING, "name") + nbt_string(name)
        + struct.pack(">b", TAG_END)
    )
    servers = named(TAG_LIST, "servers") + struct.pack(">bi", TAG_COMPOUND, 1) + server
    return named(TAG_COMPOUND, "") + servers + struct.pack(">b", TAG_END)


def main(argv):
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    with open(argv[3], "wb") as out:
        out.write(servers_dat(argv[1], argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
