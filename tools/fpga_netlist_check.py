import json, re, sys

def fail(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

def parse_int(s):
    return int(s.replace(",", ""))

def check_json(netlist_path, progress_path):
    data = json.load(open(netlist_path))
    cells = dict(data.get("cells", {}))
    for mod in data.get("modules", {}).values():
        cells.update(mod.get("cells", {}))
    lut4 = 0
    flops = 0
    names = list(cells.keys())
    for name, cell in cells.items():
        typ = cell.get("type", "")
        if typ == "SB_LUT4":
            lut4 += 1
        if typ.startswith("SB_DFF"):
            flops += 1
    required = ("st_mepc", "st_mtvec", "st_mcause", "st_mie")
    missing = []
    for req in required:
        hit = False
        for name, cell in cells.items():
            if req in name and cell.get("type", "").startswith("SB_DFF"):
                hit = True
                break
        if not hit:
            missing.append(req)
    text = open(progress_path).read()
    base_lut4 = base_flops = 0
    explained = False
    for line in text.splitlines():
        ml = re.search(r'([0-9][0-9,]*)\s*LUT4', line)
        if not ml:
            continue
        base_lut4 = parse_int(ml.group(1))
        mf = re.search(r'([0-9][0-9,]*)\s*flops', line)
        if mf:
            base_flops = parse_int(mf.group(1))
        explained = "explained" in line or "explanation" in line
    if base_lut4 == 0:
        fail("fpga_full netlist check FAILED: no LUT4 baseline found in PROGRESS.md")
    if base_lut4 == 0:
        fail("fpga_full netlist check FAILED: no LUT4 baseline found in PROGRESS.md")
    if base_flops == 0:
        base_flops = flops
    lut_drop = base_lut4 and (lut4 < base_lut4 * 9 // 10)
    flop_drop = base_flops and (flops < base_flops * 9 // 10)
    if missing:
        fail("fpga_full netlist check FAILED: missing trap CSR flops: " + " ".join(missing))
    if (lut_drop or flop_drop) and not explained:
        fail("fpga_full netlist check FAILED: "
             f"LUT4={lut4} vs baseline={base_lut4}, flops={flops} vs baseline={base_flops}; "
             "unexplained >10% FPGA netlist shrink")
    print(f"fpga_full netlist check OK: SB_LUT4={lut4} flops={flops} "
          f"baseline_lut4={base_lut4} baseline_flops={base_flops}")

check_json(sys.argv[1], sys.argv[2])
