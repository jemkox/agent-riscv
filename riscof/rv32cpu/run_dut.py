#!/usr/bin/env python3
import os
import subprocess
import sys

def die(msg):
    raise SystemExit(msg)

def project_root():
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.abspath(os.path.join(here, '..', '..'))

def get_symbols(elf, want):
    exe = 'riscv64-unknown-elf-objdump'
    out = subprocess.run([exe, '-t', elf], check=True,
                         stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                         text=True).stdout
    vals = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 5:
            name = parts[-1]
            if name in want:
                val = int(parts[0], 16)
                if val:
                    vals.setdefault(name, val)
    for name in want:
        if name in vals:
            return vals[name]
    return 0

def main(elf, sig_file):
    root = project_root()
    runner = os.path.join(root, 'build', 'vlt_riscof', 'run_hex_sig')
    tmp = os.path.join(root, 'build', 'riscof')
    os.makedirs(tmp, exist_ok=True)
    begin = get_symbols(elf, ['begin_signature', 'rvtest_sig_begin'])
    end = get_symbols(elf, ['end_signature', 'rvtest_sig_end'])
    if not begin or not end or end <= begin:
        die(f'no signature symbols in {elf}')
    binf = os.path.join(tmp, 'dut.bin')
    hexf = os.path.join(tmp, 'dut.hex')
    share = os.path.join(tmp, 'p.hex')
    cfg = os.path.join(tmp, 'p.sigcfg')
    out = os.path.join(tmp, 'p.sigout')
    subprocess.run(['riscv64-unknown-elf-objcopy', '-O', 'binary', elf, binf],
                   check=True)
    subprocess.run([sys.executable, os.path.join(root, 'tools', 'bin2hex.py'),
                    binf, hexf], check=True)
    with open(hexf, 'rb') as f, open(share, 'wb') as g:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            g.write(b)
    with open(cfg, 'w') as f:
        f.write(f'{begin:x} {end:x}\n')
    if os.path.exists(out):
        os.remove(out)
    try:
        subprocess.run([runner], cwd=root, timeout=120)
    except subprocess.TimeoutExpired:
        die(f'runner {runner} exceeded 120 s timeout (hung test?)')
    size = os.path.getsize(out)
    words = (end - begin) // 4
    if size < words * 9:
        die(f'sigout too small: {size} bytes, expected {words * 9}')
    os.replace(out, sig_file)

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
