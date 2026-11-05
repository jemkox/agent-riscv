#!/usr/bin/env python3
import sys, struct, re
if len(sys.argv) < 5:
    print("usage: cmp_qstate.py <cpu_retire.bin> <cpu_start_rec> <qtrace> <qstart_line> [limit]")
    raise SystemExit
cpu=sys.argv[1]; start_rec=int(sys.argv[2]); qlog=sys.argv[3]; qstart=int(sys.argv[4]); limit=int(sys.argv[5]) if len(sys.argv)>5 else 5000
pc_rx=re.compile(r'^\s*pc\s+([0-9a-fA-F]{1,16})\s*$')
x_rx=re.compile(r'(x\d+)/(\w+)\s+([0-9a-fA-F]{8})')
def reg_write(insn, rd):
    if rd == 0: return False
    op = insn & 0x7f
    if op in (0x23,0x27,0x2b,0x2f,0x63):
        return False
    if op == 0x73:
        return rd != 0
    return True
def states():
    with open(qlog, errors='ignore') as f:
        lineno=0
        pc=None
        for line in f:
            lineno += 1
            if lineno < qstart: continue
            m=pc_rx.match(line)
            if m:
                pc=int(m.group(1),16)
                continue
            if line.lstrip().startswith('x0/zero'):
                regs=[None]*32
                lines=[line]
                for _ in range(7):
                    l=f.readline()
                    lineno += 1
                    if not l: break
                    lines.append(l)
                for l in lines:
                    for r in x_rx.finditer(l):
                        idx=int(r.group(1)[1:])
                        if idx < 32: regs[idx]=int(r.group(3),16)
                if pc is not None:
                    yield pc, regs
cpu_file=open(cpu,'rb')
cpu_file.seek((start_rec-1)*32)
cpu_rec=cpu_file.read(32)
if len(cpu_rec)<32:
    print("no CPU record"); raise SystemExit(2)
regs=[None]*32
rec_idx=start_rec-1
qiter=states()
for n in range(limit):
    try:
        qpc,qregs=next(qiter)
    except StopIteration:
        break
    while True:
        cyc,pc,insn,rd,wv,st,ea,sd=struct.unpack('<8I',cpu_rec)
        if pc == qpc:
            break
        if reg_write(insn,rd):
            regs[rd]=wv
        rec_idx += 1
        cpu_rec=cpu_file.read(32)
        if len(cpu_rec)<32:
            print(f'CPU ended at seq={cyc} pc={pc:08x}, Q wants pc={qpc:08x} at n={n}')
            raise SystemExit(2)
    diffs=[]
    for i,q in enumerate(qregs):
        if q is None: continue
        if regs[i] is None:
            regs[i]=q
            continue
        if regs[i] != q:
            diffs.append((i, regs[i], q))
    if diffs:
        cyc,pc,insn,rd,wv,st,ea,sd=struct.unpack('<8I',cpu_rec)
        print(f'FIRST STATE MISMATCH before exec pc={qpc:08x} cpu_seq={cyc} at n={n}')
        for i,mine,q in diffs:
            print(f'  x{i}=cpu {mine:08x} qemu {q:08x}')
        print('CPU current record:', f'pc={qpc:08x} insn={cpu_rec[8:12][::-1].hex()}?')
        raise SystemExit(1)
    cyc,pc,insn,rd,wv,st,ea,sd=struct.unpack('<8I',cpu_rec)
    if reg_write(insn,rd): regs[rd]=wv
    rec_idx += 1
    cpu_rec=cpu_file.read(32)
    if len(cpu_rec)<32:
        break
print(f'OK: first {n} aligned state dumps no register mismatch')
