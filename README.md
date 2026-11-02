# RV32 CPU (DOOM edition)

A 5-stage in-order RV32IM CPU, Verilator-tested against official riscv-tests
(riscv-tests rv32ui/rv32um/selected rv32mi), a Python ISS, 15 directed tests,
N=500/5000 random differential programs, a k-induction formal model, and DOOM
running natively at 123.8M cycles / 31 rendered frames. The full CPU fits and
routes on iCE40 UP5K (4859 LC, 8 BRAM, 1 DSP, 13.16 MHz).

## ASCII diagram

```text
Full simulation CPU:

  fetch_pred / BTB (2-bit local)
        |
        v
  +--------+   +-----------+   +-----------+   +-----------+   +-----------+
  | fetch  |-> | decode/ID |-> |    EX     |-> |    MEM    |-> |    WB     |-> regs32
  +--------+   +-----------+   +-----------+   +-----------+   +-----------+
      |              |              |              |              |
    BPIF/imm32     ifdec/CSRs    ALU, branch   cache32 L1 I/D     forwarding
    pc target     rs1/rs2 read   RV32M MDU     UART+KEY MMIO     load/store
                                               (LAT 1/5/20,
                                                pending-fill)

FPGA full top (fpga_pipe_top, fits UP5K):

  16 KB I + 16 KB D direct-mapped (8x SB_RAM40_4K)  +  full pipeline
  MUL/MULH/MULHSU/MULHU: 4 cycles on one SB_MAC16 DSP; DIV/REM: ~33 restoring cycles
```

## Microarchitecture

`rtl/top_pipe.sv` is a 5-stage in-order pipeline:

- fetch + branch prediction: BTB with 2-bit local counters, `jal` predicted taken,
  mispredict = pipeline restart (measured mispred penalty ~2 cycles);
- decode/ID: `imm32`, `ifdec`, register reads, CSR stage (`mcycle`/`minstret`
  real counters, `mcountinhibit` gates them, mtime/mtimecmp timer, `xhalt`);
- EX: ALU, branch condition, M extension via `mdiu_fast.sv` (SIM) / `mdiu_fpga.sv`
  (FPGA, `SB_MAC16` DSP), 32-register file;
- MEM: `cache32.sv` L1 I/D, direct-mapped, 16 B lines, `CACHE_LAT` 1/5/20 with
  a pending-fill policy that re-forwards ID/EX operands during a fill; MMIO at
  0x1000_0000 (UART, DOOM_BIG) and 0x1FF0_0000 window (frame/key) for DOOM_BIG;
- WB: writeback with full forwarding; load-use stall; store forwarding.

DOOM_BIG backing RAM is 32 MB (word-array), WAD loaded at 0x00C0_0000.

## ISA supported

RV32 base + `M` proven by official tests: `rv32ui` ALL PASS, `rv32um` ALL PASS,
selected `rv32mi` subset (timer/CSR/ecall/ebreak/instret_overflow/misaligned
sh etc. - 15 tests) ALL PASS. Not implemented in this build: atomics (A),
S/U privilege (S), MMU (M14+ roadmap). FPGA proof top `rtl/fpga_top.sv` small
program subset (addi/lui/sw/lw/add) still exists as a small artifact.

## Verification approach

- Directed tests `tests/t01..t15` (self-checking, print `TEST PASSED (n instrs)`).
- Random differential vs the Python ISS (`iss/iss.py` + `tools/gen.py`):
  `regress N=500`/`N=5000` -> 0 mismatches, `ALL PASS`.
- Official riscv-tests (`~/downloads/riscv-tests`, read-only copies): `ui`, `um`, `mi`.
- m7 UART C programs print correct results (`ALL M7 PASS`, score 4274980064).
- Doom play test verified against a NO-KEY baseline run (key effect proven).
- FPGA: `fpga_test` simulates the full FPGA top program vs reference; `fpga_full`
  builds `build/cpu_full.bin` via yosys `synth_ice40 -dsp` + nextpnr + icepack.
- Formal: `formal/pipeline.sby` k-induction proves model-level pipeline invariants
  (`mode prove` PASS); not full ISA equivalence.

## The two bugs DOOM found (with directed tests)

1. **load-use stall + store gate** (M10c): a store parked in EX by a load-use
   stall issued its data-cache access with the not-yet-forwarded address and
   wrote a garbage address (DOOM: `sw` zeroed picolibc `_ctype_`, lump lookups
   failed). Fix: gate the data-cache access with `!stall` in `top_pipe.sv`.
   Directed test `tests/t14_ldst_stall` (failed on the old RTL, passes now).
2. **stale operands under stall** (M10d): on `stall`/`m_stall` the EX operands
   latched raw `idex_r1/r2` instead of the FORWARDED `a_ex/b_ex`; `lw s6; lw a5;
   blt a5,s6` compared a stale register (DOOM: "bad texture directory", striped
   frames). Fix: latch forwarded operands; directed test `tests/t15_ld_ld_br`
   (failed on the old RTL, passes now). Also fixed: `minstret` rollover carry in
   `rtl/csrs.sv` (rv32mi `instret_overflow`).

## Measured metrics

CPU (official suite aggregate, `CACHE_LAT=1`): UI IPC 0.889, UM IPC 0.623;
m7 C benchmarks: matmul IPC 0.856, bench IPC 0.906; branch prediction accuracy
77.314% (m7 log, `BR=5648 MISPRED=617` earlier baseline runs).

DOOM run (DOOM_BIG, CACHE_LAT=5, 32 MB RAM, WAD shareware):

```text
31 frames in            123,801,143 cycles (halt=0, frames all valid)
cycles/frame            3.99M incl. boot; render-frame deltas ~2.33M
fps at 50 MHz           12.5      fps at FPGA Fmax 13.16 MHz: 3.3
simulation speed        5.57M cycles/s (-O3 baseline), best measured 5.80M (PGO+LTO)
I/D miss rates          0.047% / 1.50%        mst 5.90% st 1.66% mispred 0.84% of branches
```

FPGA full CPU top (`fpga_pipe_top`, yosys `synth_ice40 -dsp`, nextpnr `--up5k --package sg48`):

```text
build/cpu_full.bin                produced (icepack)
LC (seed 7, PASS run)             4859/5280 (3500 LUT4 + 554 LUT+DFF + 670 DFF + 135 CARRY)
SB_RAM40_4K (BRAM)                8          SB_MAC16 DSP: 1
Fmax                                13.16 MHz routed, PASS at 13.00 MHz budget, nextpnr --seed 7
                                  (seed 2 also PASS at 13.07; seed 6 gives 12.76 - seeds shown because they matter)
Fmax history                      13.67 MHz (CSR-counter stubs), 13.20 MHz (round-5 DSP MDU base, 4710 LC)
```

FPGA small proof top (`rtl/fpga_top.sv`, `hdl make fpga`): 597/5280 LC, 8/30 RAM,
23.96 MHz, `build/cpu.bin`.

## Optimization history

- BTB + 2-bit local prediction (77.314% accuracy on m7; mispred restart).
- L1 I/D caches, 16 B lines, configurable `CACHE_LAT` 1/5/20; pending-fill with
  operand re-forwarding; DOOM_BIG grew to 16 KB + 16 KB.
- RV32M MDU; SIM idle-skip graph trim; FPGA MDU moved onto one `SB_MAC16` DSP
  (4-cycle MUL, review-item checklist).
- Word-array backing RAM + tag-matched self-mod invalidate: DOOM cycles
  124,092,703 -> 123,801,143; `-O3` applied to generated C++ via Vrun_doom.mk
  (Verilator `-O3` alone does not do that): 3.96 -> 5.57M cycles/s.
- Fmax work: parallel CSR read-selects, real counters, DSP MDU, instret-carry
  guard (F4 table in PROGRESS.md, rows 0-6 + two measured-and-reverted
  attempts).
- P2 D2 round: gprof profile; PGO+LTO 5.80M best; `--threads 2` measured 8x
  WORSE (0.69M) and rejected; 15M not reached, gap recorded honestly.

## Run commands

```sh
hdl make all_tests          # every suite: test x2 (LAT 1/5), ui um mi, regress N=500, m7, doom
hdl make test               # directed + ui/um + random N from scratch, prints ALL PASS
hdl make regress N=500      # random differential vs ISS
hdl make ui / um / mi       # official riscv-tests subsets
hdl make m7                 # UART C programs (correct results)
hdl make lat1 / lat5 / lat20
hdl make doom               # headless DOOM: 31 frames + #RUN log
hdl make play               # live SDL2 window DOOM with keyboard
hdl make play_test          # scripted DOOM vs no-key baseline (fails if keys do nothing)
hdl make fpga_full          # full CPU FPGA: build/cpu_full.bin + LC/Fmax (FPGA_FREQ/FPGA_SEED vars)
hdl make fpga               # small FPGA proof top: build/cpu.bin
hdl make fpga_test / mdiu_tb
```

## DOOM in simulation (M10)

DOOM (the shareware `doom1` WAD, port_rv32.c + the public Doom source port
compiled with `riscv64-unknown-elf-gcc -march=rv32im -mabi=rv32 -Os` against
picolibc) runs natively on the full 5-stage CPU in Verilator.

Build and run:

```sh
hdl make doom        # headless: renders 31 frames to build/doom/frames, UART log
hdl make play        # LIVE window (SDL2, DISPLAY passed into the sandbox), keyboard attached
hdl make play_test   # scripted headless play, verified vs a NO-KEY baseline run
```

`make play` controls: arrow keys = move/turn, Ctrl = fire, Space = use/open,
Enter, Esc, Y/N confirmations, 1-7 = weapon select. Keys are pushed to a FIFO
in the testbench and consumed by DOOM through an MMIO load at `0x1FF0_0008`
(`key_in/key_hit` on the cache MMIO port); the harness polls SDL events every
65536 cycles (~80 polls/s at 13 MHz).

Measured numbers (DOOM_BIG build, 16 KB I + 16 KB D direct-mapped caches, 16 B
lines, CACHE_LAT=5):

```text
31 frames in            123,801,143 cycles (halt=0)
cycles/frame            3.99M average incl. boot (render-frame deltas ~2.33M)
fps at 50 MHz           12.5        fps at FPGA Fmax 13.16 MHz: 3.3
simulation speed        5.57M cycles/s baseline (22.2 s), best measured 5.80M (PGO+LTO, 21.33 s)
I-cache miss rate       0.047%      D-cache miss rate 1.50%
M/mem-pending stalls    5.90% of cycles  load-use stalls 1.66%  mispreds 188,656/22.53M branches (0.84%)
```

Sample frames (also animated GIF `docs/doom/play_demo.gif`):
`docs/doom/title.png`, `mid.png`, `last.png` (headless doom run), and
`play_menu.png`, `play_move_a.png`, `play_move_b.png` (scripted keyboard
session: Esc opens the menu, Enter x3 + hold Up starts E1M1 and walks - verified
against the no-key baseline, first frame divergence 564/568 after first key).

Honest limits: shareware WAD only, 320x200 software-render frames, keyboard
poll granularity means very fast taps can be missed, `play` needs an X display,
simulation runs at ~1.4 real fps (P2 15M cycles/s target not reached; best 5.80M),
and the Doom cycles measured here are on the full sim CPU, not the FPGA build.

## Honest known limitations

- The full CPU FITS in UP5K (4859/5280 LC) but leaves no headroom for a second
  16 KB cache; the FPGA build is the same CPU, just 32 MB backing RAM is not
  on-FPGA (FPGA runs its small built-in program, `fpga_test` proves it).
- FPGA counters are 32-bit truncated at rollover (carry guarded `ifdef FPGA`);
  SIM has the full carry. rv32mi passes in SIM.
- No A (atomics), no S/U privilege, no MMU in this build (roadmap continues
  beyond this goal).
- Formal proof is model-level pipeline invariants (k-induction), not ISA equivalence.
- Branch-prediction accuracy is measured on the m7 benchmark; DOOM run stats
  (0.84% mispred) come from the committed `#STATS` counters.
- `mst_cnt` lumps mul/div stalls with pending-fill stalls (not separately split).
- Simulation speed best 5.80M cycles/s; the 15M target was measured and missed
  honestly (all attempts in PROGRESS.md; --threads made it 8x worse).
- Keyboard is polled every 65536 sim cycles in the live window (fine at real
  typing speed, coarse for held-key autorepeat nuances).
