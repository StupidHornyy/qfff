#!/bin/sh
set -e

as -o qfff.o qfff.s
ld -N -s --build-id=none -o qfff_raw qfff.o

python3 - "$@" << 'EOF'
import struct

with open('qfff_raw', 'rb') as f:
    data = bytearray(f.read())

e_phoff    = struct.unpack_from('<Q', data, 0x20)[0]
e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
e_phnum    = struct.unpack_from('<H', data, 0x38)[0]

max_end = 0
for i in range(e_phnum):
    off = e_phoff + i * e_phentsize
    p_offset = struct.unpack_from('<Q', data, off + 8)[0]
    p_filesz = struct.unpack_from('<Q', data, off + 32)[0]
    max_end = max(max_end, p_offset + p_filesz)

struct.pack_into('<Q', data, 0x28, 0)  # e_shoff
struct.pack_into('<H', data, 0x3a, 0)  # e_shentsize
struct.pack_into('<H', data, 0x3c, 0)  # e_shnum
struct.pack_into('<H', data, 0x3e, 0)  # e_shstrndx

with open('qfff', 'wb') as f:
    f.write(data[:max_end])
EOF

chmod +x qfff
rm -f qfff.o qfff_raw
echo "build ok: $(wc -c < qfff) bytes"
