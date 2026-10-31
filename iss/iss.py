#!/usr/bin/env python3
# RV32I reference simulator (ISS). Logs retiring instructions "pc insn rd val".
# Usage: iss.py [--quiet] [--log FILE] BINFILE
# Exit: 0 ok (ebreak reached) 2 timeout 3 illegal instruction / bad align
import sys

def main(argv):
    quiet = False; log = None; binfile = None; want_pass = False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--quiet': quiet = True
        elif a == '--pass': want_pass = True
        elif a == '--log': log = argv[i+1]; i += 2; continue
        else: binfile = a
        i += 1
    if binfile is None:
        print("usage: iss.py [--quiet] [--pass] [--log F] BIN"); return 1
    prog = open(binfile,'rb').read()
    mem = bytearray(0x40000)          # 256 KiB, word index = (a>>2)&0xFFFF
    mem[0:len(prog)] = prog
    reg = [0]*32
    pc = 0
    steps = 0
    LIM = 200000
    lines = []
    def rd8(a):  return mem[a & 0x3FFFF]
    def rw(a):   return int.from_bytes(mem[(a&0x3FFFF):(a+4)&0x3FFFF+0],'little') if False else int.from_bytes(mem[(a&0x3FFFF):((a&0x3FFFF)+4)],'little')
    def rw16(a): return int.from_bytes(mem[(a&0x3FFFF):((a&0x3FFFF)+2)],'little')
    def w8(a,v):  mem[a&0x3FFFF] = v & 0xFF
    def w16(a,v): mem[(a&0x3FFFF):((a&0x3FFFF)+2)] = (v&0xFFFF).to_bytes(2,'little')
    def w32(a,v): mem[(a&0x3FFFF):((a&0x3FFFF)+4)] = (v&0xFFFFFFFF).to_bytes(4,'little')
    def sx(v,n):  return v - (1<<n) if v & (1<<(n-1)) else v
    stopped = 0
    while steps < LIM:
        a = pc & 0x3FFFF
        ins = int.from_bytes(mem[a:a+4],'little')
        opc = ins & 0x7F; f3 = (ins>>12)&7; rd = (ins>>7)&31
        r1 = (ins>>15)&31; r2 = (ins>>20)&31
        iimm = sx((ins>>20)&0xFFF,12); simm = sx(((ins>>20)&0xFE0)|((ins>>7)&31),12)
        bimm = sx(((ins>>31)&1)<<12 | ((ins>>7)&1)<<11 | ((ins>>25)&0x3F)<<5 | ((ins>>8)&0xF)<<1, 13)
        uimm = (ins & 0xFFFFF000)
        jimm = sx(((ins>>31)&1)<<20 | ((ins>>12)&0xFF)<<12 | ((ins>>20)&1)<<11 | (((ins>>21)&0x3FF)<<1), 21)
        illegal = False; st = None; ldrd = None; slog = (0,0,0,0)
        a0 = reg[r1] if r1 else 0; a1 = reg[r2] if r2 else 0
        wv = None; wv_ok = False; npc = (pc+4) & 0xFFFFFFFF
        neg = (ins>>30)&1
        if opc == 0x33:   # OP
            sh = a1 & 31
            if   f3 == 0: wv = (a0-a1) if neg else (a0+a1)
            elif f3 == 1: wv = a0 << sh
            elif f3 == 2: wv = 1 if sx(a0,32) < sx(a1,32) else 0
            elif f3 == 3: wv = 1 if a0 < a1 else 0
            elif f3 == 4: wv = a0 ^ a1
            elif f3 == 5: wv = (sx(a0,32) >> sh) if neg else ((a0&0xFFFFFFFF) >> sh)
            elif f3 == 6: wv = a0 | a1
            else:         wv = a0 & a1
        elif opc == 0x13: # OP-IMM
            sh = iimm & 31
            if   f3 == 0: wv = a0 + iimm
            elif f3 == 1: wv = a0 << sh
            elif f3 == 2: wv = 1 if sx(a0,32) < iimm else 0
            elif f3 == 3: wv = 1 if (a0&0xFFFFFFFF) < (iimm&0xFFFFFFFF) else 0
            elif f3 == 4: wv = a0 ^ iimm
            elif f3 == 5: wv = (sx(a0,32) >> sh) if neg else ((a0&0xFFFFFFFF) >> sh)
            elif f3 == 6: wv = a0 | iimm
            else:         wv = a0 & iimm
        elif opc == 0x03: # LOAD
            ea = (a0 + iimm) & 0xFFFFFFFF
            if f3 == 2:
                ldrd = rw(ea)
            elif f3 in (1,5):
                v = rw16(ea); ldrd = sx(v,16) if f3 == 1 else v
            elif f3 in (0,4):
                v = rd8(ea); ldrd = sx(v,8) if f3 == 0 else v
            else: illegal = True
            wv = ldrd
        elif opc == 0x23: # STORE
            ea = (a0 + simm) & 0xFFFFFFFF
            if f3 == 2:
                st = (32, ea, a1)
                slog = (1, ea, a1, 0xF)
            elif f3 in (1,5):
                half = a1 & 0xFFFF
                st = (16, ea, half)
                slog = (1, ea, half << (16 * ((ea >> 1) & 1)),
                        3 << (2 * ((ea >> 1) & 1)))
            elif f3 in (0,4):
                byte = a1 & 0xFF
                st = (8, ea, byte)
                slog = (1, ea, byte << (8 * (ea & 3)),
                        1 << (ea & 3))
            else: illegal = True
        elif opc == 0x63: # BRANCH
            t = {0: a0 == a1, 1: a0 != a1, 4: sx(a0,32)<sx(a1,32), 5: sx(a0,32)>=sx(a1,32),
                 6: a0 < a1, 7: a0 >= a1}.get(f3 if f3 not in (2,3) else 99)
            if t is None: illegal = True
            elif t: npc = (pc + bimm) & 0xFFFFFFFF
        elif opc == 0x6F: # JAL
            wv = (pc+4) & 0xFFFFFFFF; npc = (pc + jimm) & 0xFFFFFFFF
        elif opc == 0x67: # JALR
            if f3: illegal = True
            wv = (pc+4) & 0xFFFFFFFF; npc = ((a0 + iimm) & 0xFFFFFFFE)
        elif opc == 0x0F:
            if rd or r1: illegal = True
        elif opc == 0x37: wv = uimm
        elif opc == 0x17: wv = (pc + uimm) & 0xFFFFFFFF
        elif opc == 0x73:
            stopped = 1
            lines.append((pc,ins,0,0,0,0,0,0)); break
        else:
            illegal = True
        if illegal:
            lines.append((pc,ins,0,0,0,0,0,0))
            if log:
                open(log,'w').write("\n".join(
                    "%08x %08x %d %08x %d %08x %08x %x" % t for t in lines) + "\n")
            print("ERR illegal at %08x insn %08x" % (pc,ins)); return 3
        written = False
        if rd and wv is not None:
            reg[rd] = wv & 0xFFFFFFFF
            written = True
        lines.append((pc,ins,rd, (wv & 0xFFFFFFFF) if written else 0, *slog))
        if st and not illegal:
            wid, ea, v = st
            if wid == 8: w8(ea, v)
            elif wid == 16: w16(ea, v)
            else: w32(ea, v)
        pc = npc; steps += 1
    else:
        if log:
            open(log,'w').write("\n".join(
                "%08x %08x %d %08x %d %08x %08x %x" % t for t in lines) + "\n")
        print("TIMEOUT after %d steps" % steps); return 2
    if log:
        open(log,'w').write("\n".join(
            "%08x %08x %d %08x %d %08x %08x %x" % t for t in lines) + "\n")
    if want_pass:
        if stopped and reg[3] == 1: return 0
        print("FAIL: gp=%d" % (reg[3] if stopped else 0)); return 1
    if not quiet: print("STEPS=%d" % steps)
    return 0

sys.exit(main(sys.argv))
