#!/usr/bin/env python3
import sys, struct

def find_props(dtb):
    if len(dtb) < 0x2c:
        return 0, []
    total = struct.unpack_from('>I', dtb, 4)[0]
    if total != len(dtb):
        # The input may already have an obsolete total size; keep the file length as authoritative.
        pass
    pos = 40 + struct.unpack_from('>I', dtb, 8)[0]
    props = []
    while pos + 8 <= len(dtb):
        tag = struct.unpack_from('>I', dtb, pos)[0]
        if tag == 0x00000001:       # NODE
            pos += 4
        elif tag == 0x00000002:     # NODE_END
            pos += 4
            break
        elif tag == 0x00000003:     # PROP
            if pos + 12 > len(dtb):
                break
            length, value_off = struct.unpack_from('>II', dtb, pos + 4)
            pos += 12
            if pos + 8 > len(dtb):
                break
            ntag, name_off = struct.unpack_from('>II', dtb, pos)
            if ntag != 0x00000009:  # NAME
                return 0, []
            pos += 8
            name_end = dtb.find(b'\0', name_off)
            if name_end < 0:
                return 0, []
            name = dtb[name_off:name_end]
            if name == b'bootargs':
                props.append((pos - 20, length, value_off))
        elif tag == 0x00000009:     # NAME
            pos += 8
        elif tag == 0x00000000:     # pad/unknown
            pos += 4
        else:
            return 0, []
    return pos, props

def patch(inpath, outpath, newargs):
    dtb = bytearray(open(inpath, 'rb').read())
    names_off, props = find_props(dtb)
    if not props:
        return 2
    # Replace only the first bootargs property.
    ppos, old_len, old_off = props[0]
    new = newargs.encode() + b'\0'
    while len(dtb) % 4:
        dtb.append(0)
    new_off = len(dtb)
    dtb.extend(new)
    while len(dtb) % 4:
        dtb.append(0)
    struct.pack_into('>II', dtb, ppos + 4, len(new), new_off)
    struct.pack_into('>I', dtb, 4, len(dtb))
    open(outpath, 'wb').write(dtb)
    return 0

if __name__ == '__main__':
    raise SystemExit(patch(sys.argv[1], sys.argv[2], sys.argv[3]) if len(sys.argv) == 4 else (print('usage: patch_bootargs.py in.dtb out.dtb "new bootargs"') or 1))
