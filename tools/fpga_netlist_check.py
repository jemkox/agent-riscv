#!/usr/bin/env python3
# Netlist size and primitive sanity for the FPGA full-CPU build.
# Usage: fpga_netlist_check.py NETLIST.json --baseline-lut4 N --baseline-flops N [TBHEX]
#        [--csr-min NAME:COUNT]...
# The baseline is pinned by the caller (Makefile), not parsed from PROGRESS.md.
# Checks: SB_LUT4/FLOPS_51 vs pinned baseline (grow allowed, shrink >10% fails),
# required primitives, forbidden primitives, named trap-CSR DFF counts (per
# family >= requested count), and optional TBHEX program sanity.
import json, sys
DEFAULT_CSR_MIN = (("st_mepc", 32), ("st_mtvec", 4), ("st_mcause", 6), ("st_mie", 4))
GOWIN_LUT_TYPES = {"LUT4"}
GOWIN_RAM_TYPES = {"DPX9B", "SDP36KE", "SDP136K", "RAM16SDP4", "RAM16SDP2", "RAM16SDP1", "DP", "SDP"}
GOWIN_MDU_TYPES = {"ALU", "PADD18", "PADD9", "MULT18X18", "MULT36X36", "MULTALU36X18"}
def main(argv):
    if len(argv) < 2:
        print("usage: fpga_netlist_check.py NETLIST.json --baseline-lut4 N --baseline-flops N [TBHEX] [--csr-min NAME:COUNT]...")
        return 1
    netlist = argv[1]
    lut4 = flps = None
    tbhex = None
    csr_min = []
    skip_csr = False
    allow_missing_prims = False
    i = 2
    while i < len(argv):
        a = argv[i]
        if a == '--baseline-lut4': lut4 = int(argv[i+1]); i += 2
        elif a == '--skip-csr': skip_csr = True; i += 1
        elif a == '--allow-missing-prims': allow_missing_prims = True; i += 1
        elif a == '--baseline-flops': flps = int(argv[i+1]); i += 2
        elif a == '--csr-min':
            s = argv[i+1]
            if ':' not in s:
                print("bad --csr-min NAME:COUNT"); return 1
            name, bits = s.split(':', 1)
            try:
                csr_min.append((name, int(bits)))
            except ValueError:
                print("bad --csr-min bits: " + s); return 1
            i += 2
        elif a.startswith('--'):
            print(f"unknown option {a}"); return 1
        else:
            tbhex = a; i += 1
    if lut4 is None or flps is None:
        print("baseline args missing: pass --baseline-lut4 N --baseline-flops N"); return 1
    if not csr_min:
        csr_min = [] if skip_csr else DEFAULT_CSR_MIN
    d = json.load(open(netlist))
    insts = {}
    def collect(mod):
        insts.update(mod.get("cells") or mod.get("instances") or {})
    if "modules" in d:
        for mod in (d.get("modules") or {}).values(): collect(mod)
    else:
        collect(d)
    types = [inst.get("type") for inst in insts.values()]
    ice_mode = any(t == "SB_LUT4" or (t or "").startswith("SB_DFF") or t in ("SB_CARRY", "SB_RAM40_4K") for t in types)
    gowin_mode = any(t in GOWIN_LUT_TYPES for t in types)
    lut4_now = flops_now = ram = dsp = 0
    if ice_mode:
        for t in types:
            if t == "SB_LUT4": lut4_now += 1
            elif t and t.startswith("SB_DFF"): flops_now += 1
            elif t == "SB_RAM40_4K": ram += 1
            elif t == "SB_MAC16": dsp += 1
        required = (("SB_CARRY", 1), ("SB_RAM40_4K", 1))
        if not allow_missing_prims:
            required += (("SB_MAC16", 1),)
        forbidden = ("SB_MUX2", "SB_OR_NOT")
        flops_prefix = "SB_DFF"
        primitive_report = f"iCE40 primitives found: SB_LUT4 {lut4_now}, SB_DFF {flops_now}, SB_RAM40_4K {ram}, SB_MAC16 {dsp}"
    elif gowin_mode:
        for t in types:
            if t in GOWIN_LUT_TYPES: lut4_now += 1
            elif t and t.startswith("DFF"): flops_now += 1
            elif t in GOWIN_RAM_TYPES: ram += 1
            elif t in GOWIN_MDU_TYPES: dsp += 1
        required = (("IBUF", 1), ("OBUF", 1))
        if not allow_missing_prims:
            required += (("ALU", 1),)
        forbidden = ()
        flops_prefix = "DFF"
        primitive_report = f"Gowin primitives found: LUT-family {lut4_now}, DFF-family {flops_now}, RAM {ram}, MDU/ALU {dsp}"
    else:
        print("unknown netlist primitive target: no SB_LUT4/SB_DFF or Gowin LUT/DFF types found")
        return 1
    if lut4_now < lut4:
        pct = 100.0 * (lut4 - lut4_now) / lut4
        if pct > 10.0:
            print(f"UNEXPLAINED SHRINK: LUT4-family {lut4_now} vs pinned baseline {lut4} ({pct:.1f}%); ask why and update baseline")
            return 1
    if flops_now < flps:
        pct = 100.0 * (flps - flops_now) / flps
        if pct > 10.0:
            print(f"UNEXPLAINED SHRINK: flops {flops_now} vs pinned baseline {flps} ({pct:.1f}%); ask why and update baseline")
            return 1
    print(f"netlist: LUT4-family {lut4_now} vs pinned baseline {lut4}; DFF-family flops {flops_now} vs pinned baseline {flps}")
    ok = True
    for need, minneed in required:
        n = sum(1 for t in types if t == need)
        if n < minneed:
            print(f"missing required primitive {need} (found {n}, need >= {minneed})"); ok = False
    if gowin_mode and not allow_missing_prims and ram < 1:
        print("missing Gowin RAM primitive (DP/DPX9B/SDP/RAM16SDP*)"); ok = False
    for t in types:
        if ice_mode and t in forbidden:
            print(f"forbidden primitive {t}"); ok = False
    # Required trap-state DFF instances by (sub)name: named trap CSRs must be
    # real flops in the netlist, with at least the requested live bit count.
    def csr_match(nm, need):
        base = need[3:] if need.startswith("st_") else need
        return need in nm or ("after_" + base) in nm
    for need, need_count in csr_min:
        n = sum(1 for nm, inst in insts.items()
                if csr_match(nm, need) and str(inst.get("type") or "").startswith(flops_prefix))
        if n < need_count:
            print(f"missing trap-CSR DFF bits {need} (found {n}, need >= {need_count})"); ok = False
        else:
            print(f"trap-CSR DFF {need}: {n} instance(s) (need >= {need_count})")
    print(primitive_report)
    if tbhex is not None:
        try:
            raw = open(tbhex).read()
        except OSError as e:
            print(f"missing TBHEX: {tbhex}")
            return 1
        lines = [l for l in raw.split("\n") if l.strip()]
        if any(l.strip() == "@" for l in lines):
            print("bare @ lines in TBHEX (truncated program):")
            for n, l in enumerate(lines):
                if l.strip() == "@":
                    print(f"line {n+1}: {l}")
            return 1
        try:
            vals = [int(l,16) for l in lines if l.strip()]
        except ValueError as e:
            print(f"bad TBHEX line: {e}"); return 1
        words = len(vals)
        print(f"TBHEX {tbhex}: {words} words, max value 0x{max(vals):x}, {max(vals).bit_length()} bits (expect 32-bit program words)")
        if max(vals) > 0xFFFFFFFF or max(vals).bit_length() < 12:
            print(f"TBHEX {tbhex}: bad program: {max(vals).bit_length()}-bit values, expected 32-bit instruction words")
            return 1
    if not ok: return 1
    if lut4_now == 0 or flops_now == 0:
        print("empty/degenerate netlist suspected"); return 1
    print("netlist sanity checks passed")
    return 0
if __name__ == "__main__": sys.exit(main(sys.argv))
