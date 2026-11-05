#!/usr/bin/env python3
import sys, struct

def main(argv):
    if len(argv) < 4:
        print("usage: tools/rv32dis.py <file> <start> <stop> [binary|elf] [vma]")
        return 1
    path = argv[1]
    start = int(argv[2], 0)
    stop = int(argv[3], 0)
    kind = argv[4] if len(argv) > 4 else 'elf'
    vma = int(argv[5], 0) if len(argv) > 5 else 0
    data = open(path, 'rb').read()
    if kind == 'elf':
        if data[:4] != b'\x7fELF':
            return 2
        e_phoff = struct.unpack_from('<I', data, 0x1c)[0]
        e_phnum = struct.unpack_from('<H', data, 0x2c)[0]
        blobs = []
        for i in range(e_phnum):
            off = e_phoff + i*32
            p_type = struct.unpack_from('<I', data, off)[0]
            if p_type != 1:
                continue
            p_off, p_vaddr, p_filesz, p_memsz = struct.unpack_from('<IIII', data, off+4)
            p_align = struct.unpack_from('<I', data, off+28)[0]
            if start >= p_vaddr and start < p_vaddr + max(p_filesz,p_memsz):
                blobs.append((p_off, p_vaddr, p_filesz))
        if not blobs:
            return 3
    else:
        blobs = [(0, vma, len(data))]
    for off, base, size in blobs:
        if not size:
            continue
        for addr in range(start & ~3, stop, 4):
            file_off = off + (addr - base)
            if file_off + 4 > len(data):
                continue
            insn = struct.unpack_from('<I', data, file_off)[0]
            print("%08x: %08x %s" % (addr, insn, dis(insn)))
    return 0

REG = [f"x{i}" for i in range(32)]
ABI = ["zero","ra","sp","gp","tp","t0","t1","t2","s0","s1","a0","a1","a2","a3","a4","a5","a6","a7",
       "s2","s3","s4","s5","s6","s7","s8","s9","s10","s11","t3","t4","t5","t6"]
def reg(i): return ABI[i]
def sx(v,b): return v - (1<<b) if v & (1<<(b-1)) else v
def jal_imm(i):
    b31=(i>>31)&1; b19_12=(i>>12)&0xff; b11=(i>>20)&1; b10_1=(i>>21)&0x3ff
    v=(b31<<20)|(b19_12<<12)|(b11<<11)|(b10_1<<1)
    return sx(v,21)
def dis(i):
    op=i&0x7f
    rd=(i>>7)&0x1f
    f3=(i>>12)&7
    rs1=(i>>15)&0x1f
    rs2=(i>>20)&0x1f
    imm_i=sx((i>>20)&0xfff,12)
    imm_u=(i>>12)
    imm_s=sx((((i>>25)&0x7f)<<5)|((i>>7)&0x1f),12)
    if op==0x37: return f"lui {reg(rd)},0x{imm_u:05x}"
    if op==0x17: return f"auipc {reg(rd)},{imm_u}"
    if op==0x6f:
        o=jal_imm(i)
        return f"jal {reg(rd)},{o}"
    if op==0x67:
        return f"jalr {reg(rd)},{reg(rs1)},{imm_i}"
    if op==0x63:
        b31=(i>>31)&1; b30_25=(i>>25)&0x3f; b11=(i>>7)&1; b4_1=(i>>8)&0xf
        v=(b31<<12)|(b30_25<<5)|(b11<<11)|(b4_1<<1)
        bimm=sx(v,13)
        if f3==0: return f"beq {reg(rs1)},{reg(rs2)},{bimm}"
        if f3==1: return f"bne {reg(rs1)},{reg(rs2)},{bimm}"
        if f3==4: return f"blt {reg(rs1)},{reg(rs2)},{bimm}"
        if f3==5: return f"bge {reg(rs1)},{reg(rs2)},{bimm}"
        if f3==6: return f"bltu {reg(rs1)},{reg(rs2)},{bimm}"
        return f"bgeu {reg(rs1)},{reg(rs2)},{bimm}"
    if op==0x3:
        imm=imm_i
        if f3==0: return f"lb {reg(rd)},{imm}({reg(rs1)})"
        if f3==1: return f"lh {reg(rd)},{imm}({reg(rs1)})"
        if f3==2: return f"lw {reg(rd)},{imm}({reg(rs1)})"
        if f3==4: return f"lbu {reg(rd)},{imm}({reg(rs1)})"
        if f3==5: return f"lhu {reg(rd)},{imm}({reg(rs1)})"
    if op==0x23:
        imm=imm_s
        if f3==0: return f"sb {reg(rs2)},{imm}({reg(rs1)})"
        if f3==1: return f"sh {reg(rs2)},{imm}({reg(rs1)})"
        if f3==2: return f"sw {reg(rs2)},{imm}({reg(rs1)})"
    if op==0x13:
        imm=imm_i
        if f3==0: return f"addi {reg(rd)},{reg(rs1)},{imm}"
        if f3==1: return f"slli {reg(rd)},{reg(rs1)},{i>>20}"
        if f3==2: return f"slti {reg(rd)},{reg(rs1)},{imm}"
        if f3==3: return f"sltiu {reg(rd)},{reg(rs1)},{imm}"
        if f3==4: return f"xori {reg(rd)},{reg(rs1)},{imm}"
        if f3==6: return f"ori {reg(rd)},{reg(rs1)},{imm}"
        if f3==7: return f"andi {reg(rd)},{reg(rs1)},{imm}"
        if f3==5: return f"srli/srai {reg(rd)},{reg(rs1)} shamt {(i>>20)&0x1f}"
    if op==0x33:
        if f3==0x0 and ((i>>25)&0x3f)==0: return f"add {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==0x0 and ((i>>25)&0x3f)==0x20: return f"sub {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==1: return f"sll {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==5: return f"srl/sra {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==6: return f"or {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==7: return f"and {reg(rd)},{reg(rs1)},{reg(rs2)}"
        if f3==4: return f"xor {reg(rd)},{reg(rs1)},{reg(rs2)}"
    if op==0x73:
        csr=(i>>20)
        if f3==1: return f"csrrw {reg(rd)},0x{csr:03x},{reg(rs1)}"
        if f3==2: return f"csrrs {reg(rd)},0x{csr:03x},{reg(rs1)}"
        if f3==3: return f"csrrc {reg(rd)},0x{csr:03x},{reg(rs1)}"
        if f3==5: return f"csrrwi {reg(rd)},0x{csr:03x},{rs1}"
        if f3==6: return f"csrrsi {reg(rd)},0x{csr:03x},{rs1}"
        return f"cs {reg(rd)},0x{csr:03x},{reg(rs1)}"
    return f".word 0x{i:08x}"

if __name__ == "__main__":
    sys.exit(main(sys.argv))
