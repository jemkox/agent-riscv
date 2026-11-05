#!/usr/bin/env python3
# Wrap a flat RV32 binary into a minimal ET_EXEC ELF32 with one PT_LOAD.
import struct, sys
inp, outp = sys.argv[1], sys.argv[2]
base = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x80000000
data = open(inp, 'rb').read()
n = len(data)
ehsize, phoff, phentsize, phnum = 52, 52, 32, 1
fdata = ehsize + phentsize * phnum
ident = b'\x7fELF' + bytes([1, 1, 1, 0, 0]) + b'\0' * 7
assert len(ident) == 16
eh = ident + struct.pack('<HHIIIIIHHHHHH',
                         2, 0xf3, 1, base, phoff, 0, 0,
                         ehsize, phentsize, phnum, 0, 0, 0)
assert len(eh) == 52, len(eh)
ph = struct.pack('<IIIIIIII',
                 1, fdata, base, base, n, n, 5, 0x1000)
assert len(ph) == 32
pad = b'\0' * (fdata - 52 - 32)
open(outp, 'wb').write(eh + ph + pad + data)
print('wrote', outp)
