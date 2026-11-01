#!/usr/bin/env python3
# Sum #SUMMARY INSN=n CYCLES=c lines from runner logs.
import sys
ins = cyc = 0
for fn in sys.argv[1:]:
    try:
        f = open(fn)
    except OSError:
        continue
    for ln in f:
        if ln.startswith("#SUMMARY"):
            for tok in ln.split():
                if tok.startswith("INSN="):
                    ins += int(tok[5:])
                elif tok.startswith("CYCLES="):
                    cyc += int(tok[7:])
    f.close()
print(f"INSTR={ins} CYCLES={cyc} IPC={ins / cyc if cyc else 0:.3f}")
