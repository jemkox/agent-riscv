#!/usr/bin/env python3
# RV32I reference simulator (ISS). Logs retiring instructions "pc insn rd val".
# Standard M-mode trap model (L1): traps always; mstatus MIE/MPIE/MPP per spec;
# CLINT MMIO timer at 0x0200_0000 (mtime ticks once per retired instruction).
# Exit: 0 ok (halt via xhalt CSR or timeout-with-gp) 2 timeout 3 illegal-halt
import sys

def main(argv):
    quiet = False; log = None; binfile = None; want_pass = False; linux_mpp = False; high = False
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--quiet': quiet = True
        elif a == '--pass': want_pass = True
        elif a == '--linux-mpp': linux_mpp = True
        elif a == '--high': high = True
        elif a == '--log': log = argv[i+1]; i += 2; continue
        else: binfile = a
        i += 1
    if binfile is None:
        print("usage: iss.py [--quiet] [--pass] [--log F] BIN"); return 1
    prog = open(binfile,'rb').read()
    mem = bytearray(0x100000)         # 1 MiB; identity mode wraps at MMASK[0] (256 KiB unless Sv32 is on)
    MMASK = [0x3FFFF]
    mem[0:len(prog)] = prog
    reg = [0]*32
    pc = 0x80000000 if high else 0
    steps = 0
    LIM = 200000
    lines = []
    mask = 0xFFFFFFFF
    # RV32 privilege modes (L5): M=3, S=1, U=0.  mstatus.MPP holds the saved
    # privilege (2 bits at [11:10]); mstatus.SPP (bit 8) the supervisor's saved
    # privilege for SRET.  Trap routing follows medeleg/mideleg so that U/S-mode
    # traps go to the S handler (stvec/sepc/scause/stval/spp) when delegated, and
    # machine-mode traps go to the M handler.  With medeleg=mideleg=0 and the
    # CPU in M mode this is identical to the pre-L5 M/U model, so L1-L4 and the
    # rv32mi suite behavior is unchanged; misa advertises S and U (bit18/bit20).
    cs = {0x300:0x1800,0x305:0,0x341:0,0x342:0,0x343:0,0xb00:0,0xb02:0,0x3ff:0,
          0x340:0,0x301:0x40001101,0xb82:0,0x320:0,0xc02:0,0xc82:0,0x304:0,
          0x302:0,0x303:0,0x306:0,
          0x100:0,0x104:0,0x105:0,0x106:0,0x140:0,0x141:0,0x142:0,0x143:0,0x144:0,0x180:0,
          0x32d:0,0x32e:0,0x32f:0}
    priv = 3   # current privilege: 3 = M, 1 = S, 0 = U
    SSTATUS_MASK = 0x800C1922   # SD | SUM(18) | MXR(19) | MPP(12:11) | SPP | SPIE | SIE (rv32 encoding.h masks)
    SUM_BIT = 0x00040000; MXR_BIT = 0x00080000
    MPP_MASK = 0x1800; SPP_BIT = 0x100; MPIE_BIT = 0x80; SPIE_BIT = 0x20
    MIE_BIT = 0x8; SIE_BIT = 0x2
    TSR_BIT = 0x00400000; TVM_BIT = 0x00100000
    def xret_num(n): return n in (0xb02,0xb82,0xc02,0xc82)
    def cs_get(n):
        if n == 0x100:   return cs[0x300] & SSTATUS_MASK   # sstatus = mstatus view
        if n == 0x308 or n == 0x344:   return mip_bits()
        if n == 0x32d:   return cs[0x300] & SPP_BIT
        if n == 0x32e:   return cs[0x300] & 0x10
        if n == 0x32f:   return cs[0x300] & SPIE_BIT
        if n == 0xb02 or n == 0xc02: return cs[0xb02]
        if n == 0xb82 or n == 0xc82: return cs[0xb82]
        return cs.get(n,0)
    def cs_set(n,v):
        nonlocal mip_sw
        if n == 0x301:
            pass
        elif n == 0x100:   # sstatus write: merge S-visible bits into mstatus
            cur = cs[0x300]
            cs[0x300] = (cs[0x300] & ~SSTATUS_MASK) | (v & SSTATUS_MASK)
        elif n == 0x300:
            mpp = v & MPP_MASK
            if mpp not in (0, 0x800, MPP_MASK):
                mpp = MPP_MASK
            cs[n] = ((v & ~MPP_MASK) | mpp) & mask
        elif n == 0x320:
            cs[n] = v & 0x7
        elif n == 0x180:   # satp: keep MODE(bit31) + PPN[21:0], drop ASID[30:22]
            cs[n] = ((v & 0x80000000) | (v & 0x3FFFFF)) & mask
            if v & 0x80000000: MMASK[0] = 0xFFFFF
        elif n == 0x308 or n == 0x344:
            mip_sw = v & 0xFFFFFF77
        elif n == 0xc02:
            cs[0xb02] = v & mask
        elif n == 0xc82:
            cs[0xb82] = v & mask
        elif n in cs:
            cs[n] = v & mask
    def csr_priv(n):
        # machine-mode-only CSRs require M; supervisor CSRs require S; else U.
        # 0x3ff is the test-halt extension: accessible in every mode.
        if n == 0x3ff:
            return 0
        if 0x300 <= n <= 0x3ff or n in (0xb00,0xb80,0xb02,0xb82,0xc02,0xc82,0xf00):
            return 3
        if 0x100 <= n <= 0x1ff:
            return 1
        return 0
    def mret_mstatus(high_pc=False):   # high/Linux model: MIE<-MPIE, MPP cleared, mode from saved MPP
        nonlocal priv
        m = cs_get(0x300)
        mpp = (m & MPP_MASK) >> 11
        if high_pc:
            cs[0x300] = ((m & ~(MPIE_BIT | MIE_BIT | MPP_MASK)) |
                         (MIE_BIT if (m & MPIE_BIT) else 0)) & mask
        else:
            cs[0x300] = ((m & ~(MPIE_BIT | MIE_BIT | MPP_MASK)) |
                         (MIE_BIT if (m & MPIE_BIT) else 0) | (mpp << 11)) & mask
        priv = 3 if mpp == 3 else (1 if mpp == 1 else 0)
    def trap_mstatus():   # to M handler: MPIE<-MIE, MIE<-0, MPP<-priv, priv<-M
        nonlocal priv
        m = cs_get(0x300)
        cs[0x300] = ((m & ~(MPIE_BIT | MIE_BIT | MPP_MASK)) |
                     (MPP_MASK if priv == 3 else 0x800 if priv == 1 else 0) |
                     (MPIE_BIT if (m & MIE_BIT) else 0)) & mask
        priv = 3
    def sret_mstatus():   # to S handler: SIE<-SPIE, SPP<-U, MPP<-returned priv, priv<-saved SPP
        nonlocal priv
        m = cs_get(0x300)
        sp = 1 if (m & SPP_BIT) else 0
        cs[0x300] = ((m & ~(SPIE_BIT | SIE_BIT | SPP_BIT | MPP_MASK)) |
                     (SIE_BIT if (m & SPIE_BIT) else 0) | (sp << 11)) & mask
        priv = sp
    def trap_s():   # to S handler: SPIE<-SIE, SIE<-0, SPP<-priv, MPP<-priv, priv<-S
        nonlocal priv
        m = cs_get(0x300)
        cs[0x300] = ((m & ~(SPIE_BIT | SIE_BIT | SPP_BIT | MPP_MASK)) |
                     (SPP_BIT if priv != 3 else 0) |
                     ((priv & 3) << 11) |
                     (SPIE_BIT if (m & SIE_BIT) else 0)) & mask
        priv = 1
    def clint_off(ea):    # slot offset inside the 64 KiB CLINT window or None
        if (ea & 0xFFFF0000) != 0x02000000: return None
        return ea & 0xFFFF
    CLW = 0xFFFFFFFFFFFFFFFF
    msip = 0
    mtime = 0
    mtpcmp = 0xFFFFFFFFFFFFFFFF
    mip_sw = 0   # software-set pending bits; live MSI bit3 / MTI bit7 come from CLINT
    def mip_bits():
        return (((1 << 7) if mtime >= mtpcmp else 0) |
                ((1 << 3) if (msip & 1) else 0) |
                (mip_sw & 0xFFFFFF77))
    def irq_bits():
        b = cs_get(0x304) & mip_bits()
        if priv == 3:
            return b if (cs_get(0x300) & MIE_BIT) else 0
        nd = b & ~cs.get(0x303,0)
        dl = b & cs.get(0x303,0)
        return ((nd if (cs_get(0x300) & MIE_BIT) else 0) |
                (dl if (cs_get(0x300) & SIE_BIT) else 0)) & mask
    def tvec(v, c):
        base = v & ~1
        return (base | (((v & 1) * ((c & 31) << 2)))) & mask
    # ---- Sv32 MMU (L6): two-level walk, hardware A/D update, PF causes 12/13/15.
    # typ: 0 fetch, 1 load (incl LR), 2 store (incl SC/AMO). Returns PA, or None for
    # a page fault. With satp.MODE=0 addresses are identity (pre-L6 behavior intact).
    def xlate(v, typ):
        if not (cs.get(0x180,0) & 0x80000000): return v
        root = (cs[0x180] & 0x3FFFFF) << 12
        vpn = ((v >> 12) & 0x3FF, (v >> 22) & 0x3FF)   # vpn[1] = bits 31:22, vpn[0] = bits 21:12
        pte = 0; addr = 0; lvl = 0; leaf = False
        for i in (1,0):
            addr = root + vpn[i]*4
            pte = rw(addr)
            if not (pte & 1): return None
            ppn = pte >> 10
            if pte & 0xE:
                leaf = True; lvl = i
                if i == 1 and (ppn & 0x3FF): return None  # misaligned megapage
                break
            root = ppn << 12
        if not leaf: return None          # level-0 PTE with no perms is invalid
        r = (pte >> 1) & 1; w = (pte >> 2) & 1; x = (pte >> 3) & 1; u = (pte >> 4) & 1
        pa = (((pte >> 10) << 12) | (v & (0x3FFFFF if lvl == 1 else 0xFFF)))
        ok = True
        if typ == 0:
            if not x: ok = False
            if u and priv == 1 and typ == 0 and not (cs[0x300] & SUM_BIT): ok = False   # S fetch of U page needs SUM; M may
        elif typ == 1:
            if not (r or (w and (cs[0x300] & MXR_BIT))): ok = False
        else:
            if not w: ok = False
        if priv == 0 and not u: ok = False
        if priv == 1 and u and typ != 0 and not (cs[0x300] & SUM_BIT): ok = False
        if not ok: return None
        if not (pte & 0x40) or (typ == 2 and not (pte & 0x80)):
            w32(addr, (pte | 0x40 | (0x80 if typ == 2 else 0)) & mask)  # A/D hardware update
        return pa
    def do_trap(c, val=0):
        cs[0x341] = pc & mask; cs[0x343] = val & mask
        if priv != 3 and (cs.get(0x302,0) >> c) & 1:   # delegate to S
            cs[0x141] = pc & mask; cs[0x142] = c & mask; cs[0x143] = val & mask
            trap_s(); return tvec(cs_get(0x105), c)
        cs[0x342] = c & mask; trap_mstatus()
        return tvec(cs_get(0x305), c)
    def do_irq():
        b = irq_bits()
        c = 0x80000000 | ((b & -b).bit_length() - 1)
        cs[0x343] = 0
        if priv != 3 and (cs.get(0x303,0) >> (c & 31)) & 1:
            cs[0x141] = pc & mask; cs[0x142] = c & mask; cs[0x143] = 0
            trap_s(); return tvec(cs_get(0x105), c)
        cs[0x341] = pc & mask; cs[0x342] = c
        trap_mstatus()
        return tvec(cs_get(0x305), c)
    def retire_counters(xret=False):
        nonlocal mtime
        if not (cs.get(0x320,0) & 1):
            cs[0xb00] = (cs[0xb00] + 1) & mask
        if not (xret or (cs.get(0x320,0) & 4)):
            old = cs[0xb02]
            cs[0xb02] = (cs[0xb02] + 1) & mask
            if cs[0xb02] == 0: cs[0xb82] = (cs[0xb82] + 1) & mask
        mtime = (mtime + 1) & CLW   # CLINT mtime ticks per retire (not inhibit-gated)
    def rd8(a):  return mem[a & MMASK[0]]
    def rw(a):   return int.from_bytes(mem[(a&MMASK[0]):((a&MMASK[0])+4)],'little')
    def rw16(a): return int.from_bytes(mem[(a&MMASK[0]):((a&MMASK[0])+2)],'little')
    def w8(a,v):  mem[a&MMASK[0]] = v & 0xFF
    def w16(a,v): mem[(a&MMASK[0]):((a&MMASK[0])+2)] = (v&0xFFFF).to_bytes(2,'little')
    def w32(a,v): mem[(a&MMASK[0]):((a&MMASK[0])+4)] = (v&0xFFFFFFFF).to_bytes(4,'little')
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
        apa = xlate(pc, 0)
        if apa is None:
            pc = do_trap(12, pc); steps += 1
            continue
        ins = rw(apa)
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
            else:
                pa = xlate(ea, 1 if f5 == 0x02 else 2)
                if pa is None:
                    cause = 13 if f5 == 0x02 else 15; illegal = True
                elif (pa & 0xFFFF0000) == 0x02000000 or (pa & 0xFFFFF000) == 0x10000000:
                    illegal = True   # atomics to MMIO stay illegal, like pre-L6
                elif f5 == 0x02 and rs2f == 0:  # LR.W
                    wv = rw(pa)
                    res_v = True; res_a = ea
                elif f5 == 0x03:               # SC.W
                    ok = res_v and res_a == ea
                    if ok:
                        w32(pa, a1)
                        slog = (1, pa, a1 & mask, 0xF)
                    res_v = False
                    wv = 0 if ok else 1
                elif f5 in (0x00,0x01,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C):  # AMO*.W
                    old_v = rw(pa)
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
            pa = xlate(ea, 1)
            if pa is None: cause = 13; illegal = True; pa = ea
            clw = clint_off(pa)
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
                ldrd = rw(pa)
            elif f3 in (1,5):
                v = rw16(pa); ldrd = sx(v,16) if f3 == 1 else v
            elif f3 in (0,4):
                v = rd8(pa); ldrd = sx(v,8) if f3 == 0 else v
            else: illegal = True
            wv = ldrd
        elif opc == 0x23: # STORE
            ea = (a0 + simm) & 0xFFFFFFFF
            pa = xlate(ea, 2)
            if pa is None: cause = 15; illegal = True; pa = ea
            elif f3 == 2:
                st = (32, pa, a1)
                slog = (1, pa, a1, 0xF)
            elif f3 in (1,5):
                half = a1 & 0xFFFF
                st = (16, pa, half)
                slog = (1, pa, half << (16 * ((ea >> 1) & 1)),
                        3 << (2 * ((ea >> 1) & 1)))
            elif f3 in (0,4):
                byte = a1 & 0xFF
                st = (8, pa, byte)
                slog = (1, pa, byte << (8 * (ea & 3)),
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
                if csr_num == 0x302:   # MRET
                    if priv < 3: cause = 2; illegal = True
                    elif irq_p:
                        pc = do_irq(); steps += 1
                        continue
                    else:
                        mret_mstatus((pc & 0x80000000) != 0)
                        npc = cs_get(0x341) & mask
                elif csr_num in (0x102, 0x106):   # SRET
                    if priv < 1 or (priv == 1 and (cs_get(0x300) & TSR_BIT)):
                        cause = 2; illegal = True
                    else:
                        sret_mstatus()
                        npc = cs_get(0x141) & mask
                elif csr_num in (0x100, 0x105): # WFI builder aliases (also sstatus/stvec read via f3!=0)
                    if irq_p:
                        pc = do_irq(); steps += 1
                        continue
                    npc = (pc+4) & mask
                elif csr_num == 0:
                    pc = do_trap(8 + priv); steps += 1  # ECALL: M 11, S 9, U 8
                    continue
                elif csr_num == 1:
                    pc = do_trap(3, pc); steps += 1    # EBREAK: mtval = epc
                    continue
                elif (ins >> 25) & 0x7f == 0x9 and rd == 0:   # SFENCE.VMA (real encoding)
                    if priv < 1 or (priv == 1 and (cs_get(0x300) & TVM_BIT)):
                        cause = 2; illegal = True
                    else:
                        npc = (pc+4) & mask
                else:
                    cause = 2; illegal = True
            elif f3 in (1,2,3,5,6,7):
                if irq_p:
                    pc = do_irq(); steps += 1
                    continue
                if priv < csr_priv(csr_num):
                    cause = 2; illegal = True   # CSR not accessible at current priv
                elif csr_num == 0x180 and priv == 1 and (cs_get(0x300) & TVM_BIT):
                    cause = 2; illegal = True   # satp access illegal in S when mstatus.TVM
                else:
                    if csr_num == 0x308 or csr_num == 0x344:   # mip: live bits, post-tick view like the RTL
                        old = ((((mtime + 1) >= mtpcmp) << 7) |
                               ((msip & 1) << 3) | (mip_sw & 0xFFFFFF77))
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
                    if wena: cs_set(csr_num,newv)
                    if (csr_num == 0x3ff) and (newv & 1):
                        stopped = 1
                        break
                    npc = (pc+4) & mask
                    pc = npc; steps += 1
                    continue
                if illegal:
                    pc = do_trap(2, ins); steps += 1
                    continue
            else:
                illegal = True
        else:
            illegal = True
        if illegal:
            pc = do_trap(cause, ins if cause == 2 else
                         (npc if cause == 0 else
                          (ea if cause in (4,5,6,7,13,15) else 0))); steps += 1
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
