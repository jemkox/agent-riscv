#!/usr/bin/env python3
# bin2hex.py IN.BIN OUT.HEX  -- one 32-bit little-endian word per line
import sys
d = bytearray(open(sys.argv[1],'rb').read())
if len(d) % 4: d += b'\0' * (4 - len(d) % 4)
out = open(sys.argv[2],'w')
for i in range(0, len(d), 4):
    out.write("%08x\n" % int.from_bytes(d[i:i+4],'little'))
out.close()
