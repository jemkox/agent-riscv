#!/usr/bin/env python3
# Compare CPU DBG TIMERFLUSH pcs with QEMU riscv_cpu_do_interrupt epcs.
# args: [limit] cpu_log qemu_log
import sys, re

def cpu_iter(path):
    seen=None
    with open(path,'rb') as f:
        for line in f:
            if b'TIMERFLUSH' not in line: continue
            m = re.search(rb'pc=([0-9a-fA-F]{8})', line)
            if not m: continue
            pc=m.group(1).decode()
            if pc==seen: continue
            seen=pc
            yield int(pc,16)

def qemu_iter(path):
    for line in open(path,'rb'):
        if b'do_interrupt' not in line: continue
        if b'epc:' not in line: continue
        m = re.search(rb'epc:(0x[0-9a-fA-F]+)', line)
        if m: yield int(m.group(1),16)

def main(argv):
    lim = int(argv[1]) if len(argv)>1 else 20
    cpu = cpu_iter(argv[2]) if len(argv)>2 else iter(())
    q   = qemu_iter(argv[3]) if len(argv)>3 else iter(())
    i=0
    while i<lim:
        try: c=next(cpu)
        except StopIteration: c=None
        try: qv=next(q)
        except StopIteration: qv=None
        if c is None or qv is None:
            print('cpu=%s qemu=%s end' % ('-' if c is None else '%08x'%c,
                                          '-' if qv is None else '%08x'%qv))
            break
        if c==qv:
            print('ok %d %08x' % (i+1,c))
        else:
            print('DIFF %d cpu=%08x qemu=%08x' % (i+1,c,qv))
        i+=1
    return 0

sys.exit(main(sys.argv))
