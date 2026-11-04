#!/usr/bin/env python3
# RV32I reference simulator (ISS). Logs retiring instructions "pc insn rd val".
# Standard M-mode trap model (L1): traps always; mstatus MIE/MPIE/MPP per spec;
# CLINT MMIO timer at 0x0200_0000 (mtime ticks once per retired instruction).
# Exit: 0 ok (halt via xhalt CSR or timeout-with-gp) 2 timeout 3 illegal-halt
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
    mask = 0xFFFFFFFF
    cs = {0x300:0x1800,0x305:0,0x341:0,0x342:0,0x343:0,0xb00:0,0xb02:0,0x3ff:0,
          0x340:0,0x301:0x40001001,0xb82:0,0x320:0,0xc02:0,0xc82:0,0x304:0}
    def xret_num(n): return n in (0xb02,0xb82,0xc02,0xc82)
    def cs_get(n):
        if n == 0xb02 or n == 0xc02: return cs[0xb02]
        if n == 0xb82 or n == 0xc82: return cs[0xb82]
        return cs.get(n,0)
    def cs_set(n,v):
        if n == 0x301:
            pass
        elif n == 0x300:
            cs[n] = ((v & ~0x1800) | 0x1800) & mask   # MPP fixed M-mode
        elif n == 0x320:
            cs[n] = v & 0x7
        elif n == 0xc02:
            cs[0xb02] = v & mask
        elif n == 0xc82:
            cs[0xb82] = v & mask
        elif n in cs:
            cs[n] = v & mask
    def mret_mstatus():   # MIE <- MPIE
        m = cs_get(0x300)
        cs[0x300] = ((m & ~0x8) | (0x8 if (m & 0x80) else 0)) & mask
    def trap_mstatus():   # MPIE <- MIE, MIE <- 0
        m = cs_get(0x300)
        cs[0x300] = ((m & ~0x88) | (0x80 if (m & 8) else 0) | 0x1800) & mask
    def clint_off(ea):    # slot offset inside the 64 KiB CLINT window or None
        if (ea & 0xFFFF0000) != 0x02000000: return None
        return ea & 0xFFFF
    CLW = 0xFFFFFFFFFFFFFFFF
    msip = 0
    mtime = 0
    mtpcmp = 0xFFFFFFFFFFFFFFFF
    def mip_bits():
        return ((1<<7) if mtime >= mtpcmp else 0) | ((1<<3) if (msip & 1) else 0)
    def irq_bits():
        return (cs_get(0x304) & mip_bits()) if (cs_get(0x300) & 8) else 0
    def do_trap(c):
        cs[0x341] = pc & mask; cs[0x342] = c & mask; trap_mstatus()
        return cs_get(0x305) & mask
    def do_irq():
        b = irq_bits()
        c = 0x80000000 | (11 if (b & 0x800) else (7 if (b & 0x80) else 3))
        cs[0x341] = pc & mask; cs[0x342] = c; trap_mstatus()
        return cs_get(0x305) & mask
    def retire_counters(xret=False):
        nonlocal mtime
        if not (cs.get(0x320,0) & 1):
            cs[0xb00] = (cs[0xb00] + 1) & mask
        if not (xret or (cs.get(0x320,0) & 4)):
            old = cs[0xb02]
            cs[0xb02] = (cs[0xb02] + 1) & mask
            if cs[0xb02] == 0: cs[0xb82] = (cs[0xb82] + 1) & mask
        mtime = (mtime + 1) & CLW   # CLINT mtime ticks per retire (not inhibit-gated)
    def rd8(a):  return mem[a & 0x3FFFF]
    def rw(a):   return int.from_bytes(mem[(a&0x3FFFF):((a&0x3FFFF)+4)],'little')
    def rw16(a): return int.from_bytes(mem[(a&0x3FFFF):((a&0x3FFFF)+2)],'little')
    def w8(a,v):  mem[a&0x3FFFF] = v & 0xFF
    def w16(a,v): mem[(a&0x3FFFF):((a&0x3FFFF)+2)] = (v&0xFFFF).to_bytes(2,'little')
    def w32(a,v): mem[(a&0x3FFFF):((a&0x3FFFF)+4)] = (v&0xFFFFFFFF).to_bytes(4,'little')
    def sx(v,n):  return v - (1<<n) if v & (1<<(n-1)) else v
    def idiv(a,b):
        if b == 0: return -1
        if a == -2147483648 and b == -1: return -2147483648
        q = abs(a)//abs(b)
        if (a < 0) ^ (b < 0): q = -q
        return q
    def irem(a,b):
        if b == 0: return a
        if a == -2147483648 and b == -1: return 0
        r = abs(a) % abs(b)
        return -r if a < 0 else r
    stopped = 0
    res_v = False; res_a = 0   # LR/SC reservation (rv32A, sim CPU)
    while steps < LIM:
        a = pc & 0x3FFFF
        ins = int.from_bytes(mem[a:a+4],'little')
        opc = ins & 0x7F; f3 = (ins>>12)&7; rd = (ins>>7)&31
        r1 = (ins>>15)&31; r2 = (ins>>20)&31
        iimm = sx((ins>>20)&0xFFF,12); simm = sx(((ins>>20)&0xFE0)|((ins>>7)&31),12)
        bimm = sx(((ins>>31)&1)<<12 | ((ins>>7)&1)<<11 | ((ins>>25)&0x3F)<<5 | ((ins>>8)&0xF)<<1, 13)
        uimm = (ins & 0xFFFFF000)
        jimm = sx(((ins>>31)&1)<<20 | ((ins>>12)&0xFF)<<12 | ((ins>>20)&1)<<11 | (((ins>>21)&0x3FF)<<1), 21)
        illegal = False; st = None; ldrd = None; slog = (0,0,0,0); cause = 2; xret_write = False
        a0 = reg[r1] if r1 else 0; a1 = reg[r2] if r2 else 0
        wv = None; wv_ok = False; npc = (pc+4) & 0xFFFFFFFF
        neg = (ins>>30)&1
        irq_p = irq_bits()      # pending now; fires unless this insn traps first
        if opc == 0x33:   # OP
            op7 = (ins >> 25) & 0x7F
            sh = a1 & 31
            if op7 == 1:
                if   f3 == 0: wv = (a0*a1) & 0xFFFFFFFF
                elif f3 == 1: wv = ((sx(a0,32)*sx(a1,32)) >> 32) & 0xFFFFFFFF
                elif f3 == 2: wv = ((sx(a0,32)*a1) >> 32) & 0xFFFFFFFF
                elif f3 == 3: wv = ((a0*a1) >> 32) & 0xFFFFFFFF
                elif f3 == 4: wv = idiv(sx(a0,32), sx(a1,32)) & 0xFFFFFFFF
                elif f3 == 5: wv = (0xFFFFFFFF if a1 == 0 else a0 // a1) & 0xFFFFFFFF
                elif f3 == 6: wv = irem(sx(a0,32), sx(a1,32)) & 0xFFFFFFFF
                else:         wv = (a0 if a1 == 0 else a0 % a1) & 0xFFFFFFFF
            elif op7 not in (0,0x20):
                illegal = True
            else:
                neg = (op7 == 0x20)
                if   f3 == 0: wv = (a0-a1) if neg else (a0+a1)
                elif f3 == 1 and not neg: wv = a0 << sh
                elif f3 == 2 and not neg: wv = 1 if sx(a0,32) < sx(a1,32) else 0
                elif f3 == 3 and not neg: wv = 1 if a0 < a1 else 0
                elif f3 == 4: wv = a0 ^ a1
                elif f3 == 5: wv = (sx(a0,32) >> sh) if neg else ((a0&0xFFFFFFFF) >> sh)
                elif f3 == 6 and not neg: wv = a0 | a1
                elif f3 == 7 and not neg: wv = a0 & a1
                else: illegal = True
        elif opc == 0x13: # OP-IMM
            sh = iimm & 31
            if f3 in (1,5) and ((iimm >> 5) & 1): illegal = True
            elif f3 == 0: wv = a0 + iimm
            elif f3 == 1: wv = a0 << sh
            elif f3 == 2: wv = 1 if sx(a0,32) < iimm else 0
            elif f3 == 3: wv = 1 if (a0&0xFFFFFFFF) < (iimm&0xFFFFFFFF) else 0
            elif f3 == 4: wv = a0 ^ iimm
            elif f3 == 5: wv = (sx(a0,32) >> sh) if neg else ((a0&0xFFFFFFFF) >> sh)
            elif f3 == 6: wv = a0 | iimm
            else:         wv = a0 & iimm
        elif opc == 0x2F: # LR/SC/AMO* (A ext; aligned words; aq/rl ignored)
            ea = a0
            f5 = (ins >> 27) & 0x1F
            rs2f = (ins >> 20) & 0x1F
            if f5 == 0x02:
                amo_valid = (f3 == 2) and (rs2f == 0)
            elif f5 == 0x03:
                amo_valid = (f3 == 2)
            else:
                amo_valid = (f3 == 2) and (f5 in (0x00,0x01,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C))
            if not amo_valid:
                illegal = True
            elif ea & 3:
                cause = 4; illegal = True
            elif (ea & 0xFFFF0000) == 0x02000000 or (ea & 0xFFFFF000) == 0x10000000:
                illegal = True
            elif f5 == 0x02 and rs2f == 0:  # LR.W
                wv = rw(ea)
                res_v = True; res_a = ea
            elif f5 == 0x03:               # SC.W
                ok = res_v and res_a == ea
                if ok:
                    w32(ea, a1)
                    slog = (1, ea, a1 & mask, 0xF)
                res_v = False
                wv = 0 if ok else 1
            elif f5 in (0x00,0x01,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C):  # AMO*.W
                old_v = rw(ea)
                if   f5 == 0x00: new = (old_v + a1) & mask
                elif f5 == 0x01: new = a1 & mask
                elif f5 == 0x04: new = (old_v ^ a1) & mask
                elif f5 == 0x08: new = (old_v | a1) & mask
                elif f5 == 0x0C: new = (old_v & a1) & mask
                elif f5 == 0x10: new = old_v if sx(old_v,32) < sx(a1,32) else a1
                elif f5 == 0x14: new = old_v if sx(old_v,32) > sx(a1,32) else a1
                elif f5 == 0x18: new = old_v if old_v < a1 else a1
                else:            new = old_v if old_v > a1 else a1
                w32(ea, new)
                if res_a == ea: res_v = False
                slog = (1, ea, new & mask, 0xF)
                wv = old_v
            else:
                illegal = True
        elif opc == 0x03: # LOAD
            ea = (a0 + iimm) & 0xFFFFFFFF
            clw = clint_off(ea)
            if clw is not None:
                v32 = ({0:msip,0x800:(mtpcmp & mask),0x804:(mtpcmp>>32)&mask,
                        0x808:(mtime & mask),0x80c:(mtime>>32)&mask,
                        0x4000:(mtpcmp & mask),0x4004:(mtpcmp>>32)&mask,
                        0xBFF8:(mtime & mask),0xBFFC:(mtime>>32)&mask}.get(clw, 0))
                if   f3 == 2: ldrd = v32
                elif f3 in (1,5):
                    v = (v32 >> (16*((ea>>1)&1))) & 0xFFFF; ldrd = sx(v,16) if f3==1 else v
                elif f3 in (0,4):
                    v = (v32 >> (8*(ea&3))) & 0xFF; ldrd = sx(v,8) if f3==0 else v
                else: illegal = True
            elif f3 == 2:
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
            elif t:
                npc = (pc + bimm) & 0xFFFFFFFF
                if npc & 3: cause = 0; illegal = True
        elif opc == 0x6F: # JAL
            wv = (pc+4) & 0xFFFFFFFF; npc = (pc + jimm) & 0xFFFFFFFF
            if npc & 3: cause = 0; illegal = True
        elif opc == 0x67: # JALR
            if f3: illegal = True
            else:
                wv = (pc+4) & 0xFFFFFFFF; npc = ((a0 + iimm) & 0xFFFFFFFE)
                if npc & 3: cause = 0; illegal = True
        elif opc == 0x0F:
            if rd or r1: illegal = True
        elif opc == 0x37: wv = uimm
        elif opc == 0x17: wv = (pc + uimm) & 0xFFFFFFFF
        elif opc == 0x73:
            csr_num = (ins >> 20) & 0xFFF
            zimm = (ins >> 15) & 0x1F
            if f3 == 0:
                if csr_num == 0x302:   # MRET: back to mepc, MIE <- MPIE
                    if irq_p:
                        pc = do_irq(); steps += 1
                        continue
                    mret_mstatus()
                    npc = cs_get(0x341) & mask
                elif csr_num in (0x100, 0x105): # WFI builder aliases: 0x100 (x10000073) and 0x105 (x10500073)
                    if irq_p:
                        pc = do_irq(); steps += 1
                        continue
                    npc = (pc+4) & mask
                elif csr_num == 0:
                    pc = do_trap(11); steps += 1   # ECALL: machine ecall
                    continue
                elif csr_num == 1:
                    pc = do_trap(3); steps += 1    # EBREAK
                    continue
                else:
                    cause = 2; illegal = True
            elif f3 in (1,2,3,5,6,7):
                if irq_p:
                    pc = do_irq(); steps += 1
                    continue
                if csr_num == 0x308:   # mip: live bits, post-tick view like the RTL
                    old = (((mtime + 1) >= mtpcmp) << 7) | ((msip & 1) << 3)
                else:
                    old = cs_get(csr_num)
                if f3 == 1: newv = a0
                elif f3 == 2: newv = a0 | old
                elif f3 == 3: newv = old & ((~a0) & mask)
                elif f3 == 5: newv = zimm
                elif f3 == 6: newv = zimm | old
                else: newv = old & ((~zimm) & mask)
                wena = ((f3 == 1) or (f3 == 5) or
                        ((f3 == 2 or f3 == 3) and (r1 != 0)) or
                        ((f3 == 6 or f3 == 7) and (zimm != 0)))
                if wena and xret_num(csr_num): xret_write = True
                retire_counters(xret_write)
                if rd: reg[rd] = old
                lines.append((pc,ins,rd, old & mask, 0,0,0,0))
                if wena and csr_num != 0x308: cs_set(csr_num,newv)
                if (csr_num == 0x3ff) and (newv & 1):
                    stopped = 1
                    break
                npc = (pc+4) & mask
                pc = npc; steps += 1
                continue
            else:
                illegal = True
        else:
            illegal = True
        if illegal:
            pc = do_trap(cause); steps += 1
            continue
        if irq_p:
            pc = do_irq(); steps += 1
            continue
        written = False
        if rd and wv is not None:
            reg[rd] = wv & 0xFFFFFFFF
            written = True
        lines.append((pc,ins,rd, (wv & 0xFFFFFFFF) if written else 0, *slog))
        if st:
            wid, ea, v = st
            off = clint_off(ea)
            if off is None and ea == res_a: res_v = False   # matching store drops the reservation
            if off is not None:
                if off == 0x0:     msip = v & 1
                elif off in (0x800, 0x4000): mtpcmp = (mtpcmp & ~mask) | (v & mask)
                elif off in (0x804, 0x4004): mtpcmp = (mtpcmp & mask) | ((v & mask) << 32)
                elif off in (0x808, 0xBFF8): mtime = (mtime & ~mask) | (v & mask)
                elif off in (0x80c, 0xBFFC): mtime = (mtime & mask) | ((v & mask) << 32)
            elif wid == 8: w8(ea, v)
            elif wid == 16: w16(ea, v)
            else: w32(ea, v)
        retire_counters()
        pc = npc; steps += 1
    if log:
        open(log,'w').write("\n".join(
            "%08x %08x %d %08x %d %08x %08x %x" % t for t in lines) + "\n")
    if want_pass:
        if (stopped or cs[0x3ff]) and reg[3] == 1: return 0
        print("FAIL: gp=%d" % (reg[3] if (stopped or cs[0x3ff]) else 0)); return 1
    if not quiet: print("STEPS=%d" % steps)
    if steps >= LIM and not (stopped or cs[0x3ff]):
        print("TIMEOUT after %d steps" % steps); return 2
    return 0

sys.exit(main(sys.argv))
