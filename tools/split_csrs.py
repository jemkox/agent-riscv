import pathlib
p = pathlib.Path('rtl/csrs.sv')
lines = p.read_text().splitlines()
if len(lines) < 295:
    raise SystemExit('unexpected csrs.sv length')
# Replace the large always_comb body (1-based lines 100..195) and keep the end line.
new = lines[:98] + [
    '  always_comb begin',
    '#include "csrs_comb.svh"',
    '  end',
] + lines[196:]
p.write_text('\n'.join(new) + '\n')
