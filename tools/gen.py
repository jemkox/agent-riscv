#!/usr/bin/env python3
# gen.py SEED OUTSTEM -- random valid RV32I program (deterministic per seed).
# Layout: lui x28,1; addi x31,x31,K; BODY; addi x31,x31,-1; bne back-to-BODY; ebreak
# Invariants: rd never x28/x31; memory via x28 +-aligned off; forward branches/JAL
# only (targets never land on the loop's BNE); JALR uses absolute imm < 0x800.
import sys, random

def R(f7, r2, r1, f3, rd, opc):
    return (f7 << 25) | (r2 << 20) | (r1 << 15) | (f3 << 12) | (rd << 7) | opc

def I(imm, r1, f3, rd, opc):
    return ((imm & 0xFFF) << 20) | (r1 << 15) | (f3 << 12) | (rd << 7) | opc

def S(imm, r2, r1, opc):
    return (((imm >> 5) & 0x7F) << 25) | (r2 << 20) | (r1 << 15) | ((imm & 0x1F) << 7) | opc

def B(off, r1, r2, f3, opc):
    o = off & 0x1FFF
    s = (o >> 11) & 1
    return (s << 31) | (((o >> 5) & 0x3F) << 25) | (r2 << 20) | (r1 << 15) | (f3 << 12) | (((o >> 1) & 0xF) << 8) | (s << 7) | opc

def J(off, rd, opc):
    o = off & 0x1FFFFF
    s = (o >> 20) & 1
    return (s << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | (((o >> 12) & 0xFF) << 12) | (rd << 7) | opc

def U(imm, rd, opc):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opc

def AMO(f5, r2, r1, rd):
    # word atomics: f3=010, aq/rl=0, no offset (addr = r1 + 0)
    return (f5 << 27) | (r2 << 20) | (r1 << 15) | (0x2 << 12) | (rd << 7) | 0x2F

def NOP():
    return I(0, 0, 0, 0, 0x13)

seed = int(sys.argv[1])
out = sys.argv[2]
random.seed(seed)
K = random.randint(1, 15)
Bn = random.randint(70, 400)
# Paging class: seed%4==3 runs the body with Sv32 identity mapping on (satp set)
# + MPRV|SUM|MXR armed (MPP=U so M data accesses get TRANSLATED under U rules)
# + periodic SFENCE.VMA, so walker/TLB + MPRV paths get a differential work-out.
PAG = (seed % 4 == 3)
prog = ([U(0x80000, 5, 0x37), I(0x2, 5, 0, 5, 0x13),    # x5 = 0x80000002 (Sv32, root PPN 2)
         I(0x180, 5, 1, 0, 0x73),                       # csrrw x0, satp, x5
         U(0xE0, 6, 0x37),                              # x6 = 0x000E0000 = MPRV|SUM|MXR, MPP=U
         I(0x300, 6, 1, 0, 0x73)]                       # csrrw x0, mstatus, x6 (arm MPRV)
        if PAG else []) + [U(0x20 if PAG else 1, 28, 0x37), I(K, 31, 0, 31, 0x13)]
loop_idx = len(prog)
bne_idx = loop_idx + Bn + 1

def rdreg():
    while True:
        d = random.randint(0, 31)
        if d not in (28, 31):
            return d

def rsreg():
    return random.randint(0, 31)

def foff(mult):
    v = random.randrange(-256, 256)
    return v - (v % mult)

def fwd(i):
    mx = loop_idx + Bn + 2
    j = i + random.randint(1, 300)
    if j > mx:
        j = mx
    if j == bne_idx:
        j = mx
    return (j - i) * 4

def jalr_enc(i):
    mx = loop_idx + Bn + 2
    j = i + random.randint(2, 300)
    if j > mx:
        j = mx
    if j == bne_idx:
        j = mx
    if j <= i:
        j = i + 2
    if j > mx:
        j = mx
    if j == bne_idx:
        j = mx
    return I(j * 4, 0, 0, 0, 0x67)

KINDS = (
    'lui', 'auipc', 'jal', 'jalr', 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu',
    'lb', 'lh', 'lw', 'lbu', 'lhu', 'sb', 'sh', 'sw',
    'addi', 'slti', 'sltiu', 'xori', 'ori', 'andi', 'slli', 'srli', 'srai',
    'add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'and', 'or', 'fence',
    'mul', 'mulh', 'mulhsu', 'mulhu', 'div', 'divu', 'rem', 'remu',
    'amoadd', 'amoand', 'amoswap', 'amoor', 'amoxor', 'amomax', 'amomaxu',
     'amomin', 'amominu', 'lr', 'sc')

# PAG seeds avoid AMO/LR/SC: same-cycle paged-AMO read-vs-write rd sourcing is
# an L7/L8 item (paged atomics under Linux); L6 paging class = load/store/branch/CSR+sfence.
AMO_KINDS = ('amoadd', 'amoand', 'amoswap', 'amoor', 'amoxor', 'amomax', 'amomaxu',
             'amomin', 'amominu', 'lr', 'sc')
KINDUSE = [k for k in (KINDS + ('sfence',)) if k not in AMO_KINDS] if PAG else KINDS

def emit(kind, idx):
    d = rdreg()
    a = rsreg()
    b = rsreg()
    c = random.randrange(32)
    m = random.randint(-2047, 2047)
    if kind == 'lui':
        return U(random.randrange(1 << 20), d, 0x37)
    if kind == 'auipc':
        return U(random.randrange(1 << 20), d, 0x17)
    if kind == 'jal':
        return J(fwd(idx), d, 0x6f)
    if kind == 'jalr':
        return jalr_enc(idx)
    if kind == 'beq':
        return B(fwd(idx), a, b, 0x0, 0x63)
    if kind == 'bne':
        return B(fwd(idx), a, b, 0x1, 0x63)
    if kind == 'blt':
        return B(fwd(idx), a, b, 0x4, 0x63)
    if kind == 'bge':
        return B(fwd(idx), a, b, 0x5, 0x63)
    if kind == 'bltu':
        return B(fwd(idx), a, b, 0x6, 0x63)
    if kind == 'bgeu':
        return B(fwd(idx), a, b, 0x7, 0x63)
    if kind == 'lb':
        return I(foff(1), 28, 0, d, 0x03)
    if kind == 'lh':
        return I(foff(2), 28, 1, d, 0x03)
    if kind == 'lw':
        return I(foff(4), 28, 2, d, 0x03)
    if kind == 'lbu':
        return I(foff(1), 28, 4, d, 0x03)
    if kind == 'lhu':
        return I(foff(2), 28, 5, d, 0x03)
    if kind == 'sb':
        return S(foff(1), a, 28, 0x23)
    if kind == 'sh':
        return S(foff(2), a, 28, 0x23)
    if kind == 'sw':
        return S(foff(4), a, 28, 0x23)
    if kind == 'addi':
        return I(m, a, 0, d, 0x13)
    if kind == 'slti':
        return I(m, a, 2, d, 0x13)
    if kind == 'sltiu':
        return I(m, a, 3, d, 0x13)
    if kind == 'xori':
        return I(m, a, 4, d, 0x13)
    if kind == 'ori':
        return I(m, a, 6, d, 0x13)
    if kind == 'andi':
        return I(m, a, 7, d, 0x13)
    if kind == 'slli':
        return I(c, a, 1, d, 0x13)
    if kind == 'srli':
        return I(c, a, 5, d, 0x13)
    if kind == 'srai':
        return I(c | 0x400, a, 5, d, 0x13)
    if kind == 'add':
        return R(0, b, a, 0, d, 0x33)
    if kind == 'sub':
        return R(0x20, b, a, 0, d, 0x33)
    if kind == 'sll':
        return R(0, c, a, 1, d, 0x33)
    if kind == 'slt':
        return R(0, b, a, 2, d, 0x33)
    if kind == 'sltu':
        return R(0, b, a, 3, d, 0x33)
    if kind == 'xor':
        return R(0, b, a, 4, d, 0x33)
    if kind == 'srl':
        return R(0, c, a, 5, d, 0x33)
    if kind == 'sra':
        return R(0x20, c, a, 5, d, 0x33)
    if kind == 'and':
        return R(0, b, a, 7, d, 0x33)
    if kind == 'or':
        return R(0, b, a, 6, d, 0x33)
    if kind == 'mul':
        return R(1, b, a, 0, d, 0x33)
    if kind == 'mulh':
        return R(1, b, a, 1, d, 0x33)
    if kind == 'mulhsu':
        return R(1, b, a, 2, d, 0x33)
    if kind == 'mulhu':
        return R(1, b, a, 3, d, 0x33)
    if kind == 'div':
        return R(1, b, a, 4, d, 0x33)
    if kind == 'divu':
        return R(1, b, a, 5, d, 0x33)
    if kind == 'rem':
        return R(1, b, a, 6, d, 0x33)
    if kind == 'remu':
        return R(1, b, a, 7, d, 0x33)
    if kind == 'sfence':
        return 0x12000073
    if kind in ('lr', 'sc'):
        return AMO(0x02 if kind == 'lr' else 0x03, a if kind == 'sc' else 0, 28, d)
    if kind.startswith('amo'):
        f5 = {'amoadd': 0, 'amoand': 0xC, 'amoswap': 1, 'amoor': 8, 'amoxor': 4,
              'amomin': 0x10, 'amomax': 0x14, 'amominu': 0x18, 'amomaxu': 0x1C}[kind]
        return AMO(f5, a, 28, d)
    return I(0, 0, 0, 0, 0x0f)

for i in range(Bn):
    idx = loop_idx + i
    kind = KINDUSE[i] if i < len(KINDUSE) else random.choice(KINDUSE)
    prog.append(emit(kind, idx))

prog.append(I(-1, 31, 0, 31, 0x13))
bi = len(prog)
prog.append(B(-4 * (bi - loop_idx), 31, 0, 1, 0x63))
prog.append(I(1, 31, 6, 31, 0x13))      # ori x31,x31,1 -> always odd
prog.append(I(0x3ff, 31, 1, 0, 0x73))   # csrrw x0,0x3ff,x31 = test-exit halt

if PAG:
    # Sv32 identity pages inside the 4096-word test RAM: L1 root at PA 0x2000
    # (PPN 2), L0 at PA 0x3000 (PPN 3); leaves cover VPN0 0..0x3F (PA = VA,
    # A/D preset to skip AD walks). Code < 0x2000, data base VA 0x20000.
    NOPW = 0x00000013
    while len(prog) < 0x800:
        prog.append(NOPW)
    assert len(prog) == 0x800
    prog.append((0x3 << 10) | 0xC1)          # L1[VPN1=0] -> L0: V|A|D, perms zero => interior entry
    while len(prog) < 0xC00:
        prog.append(NOPW)
    for i in range(0x40):
        prog.append((i << 10) | 0xFF)       # leaf V|A|D|R|W|X|U (A/D preset: no AD walks)

with open(out + '.bin', 'wb') as f:
    for w in prog:
        f.write((w & 0xFFFFFFFF).to_bytes(4, 'little'))
with open(out + '.hex', 'w') as f:
    for w in prog:
        f.write("%08x\n" % (w & 0xFFFFFFFF))
print("GEN seed=%d insns=%d" % (seed, len(prog)))
