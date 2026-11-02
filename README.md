# rv32cpu: a RISC-V CPU that runs DOOM, built by a local AI agent

<p align="center">
  <img src="docs/doom/gameplay.gif" width="640" alt="DOOM E1M1 running on the rv32cpu pipeline in Verilator">
</p>

A 5-stage pipelined **RV32IM** CPU written in SystemVerilog. It passes the
official RISC-V test suites, routes on a **Lattice iCE40 UP5K** FPGA, and runs
**DOOM** (shareware, unmodified game logic) cycle-accurately in Verilator, with
a live window and keyboard.

The whole design, its tests and the Doom port were written autonomously by a
**local LLM coding agent** running on a consumer PC (no cloud model wrote the
RTL). I designed the agent setup, the task, and the verification rules it had
to obey, and reviewed the milestones. See [How it was built](#how-it-was-built).

## Results

| | |
|---|---|
| ISA | RV32I + M (mul/div) + Zicsr, machine mode, timer interrupt |
| Pipeline | 5 stages (IF ID EX MEM WB), full forwarding, load-use stall, BTB with 2-bit counters |
| Caches | 16 KB I + 16 KB D, direct-mapped, 16 B lines, configurable miss latency |
| Official tests | `rv32ui` all pass, `rv32um` all pass, 15 `rv32mi` tests pass |
| Random testing | 500–5000 random programs per run, compared instruction-by-instruction with a Python reference model: 0 mismatches |
| Formal | k-induction proof of pipeline invariants (SymbiYosys) |
| CoreMark | **3.19 CoreMark/MHz** (EEMBC CoreMark 1.0, CRCs validated, GCC 13.2 `-O2`) |
| DOOM | runs to gameplay; 3.99M cycles/frame avg (~2.3M per rendered frame), IPC 0.91 |
| FPGA (iCE40 UP5K) | 4859 / 5280 logic cells, 8 BRAM, 1 DSP, **13.16 MHz** (nextpnr seed 7) |

What that means in frames per second:

| Where | Speed |
|---|---|
| Verilator on a desktop PC (5.8M cycles/s) | ~1.4 fps, playable as a slideshow |
| Real FPGA at 13 MHz | ~3 fps (needs a board with ~8 MB RAM; see limits) |
| Same CPU at 50 MHz | ~12.5 fps |

## Benchmark: CoreMark

[EEMBC CoreMark](https://github.com/eembc/coremark) 1.0, 2K performance run,
500 iterations, on the same CPU configuration that runs Doom (16 KB + 16 KB
caches, 5-cycle memory latency), timed with the CPU's own `mcycle` counter:

```text
CoreMark 1.0 : 41.504125 / GCC13.2.0 -O2 / STACK      (reported at the 13 MHz FPGA clock)
Correct operation validated.
Total ticks 156,610,941 for 500 iterations = 313,222 cycles/iteration
=> 3.19 CoreMark/MHz      IPC 0.867, branch mispredictions 13.7%
```

For context, published numbers of well-known open-source RV32 cores
(from their READMEs; different compilers and flags, so not an exact comparison):

| Core | CoreMark/MHz |
|---|---|
| **rv32cpu (this project)** | **3.19** |
| lowRISC Ibex, maxperf config | 3.13 |
| VexRiscv, full max perf (8 KB caches) | 2.57 |
| lowRISC Ibex, small config | 2.47 |
| VexRiscv, full (4 KB caches) | 2.30 |

This is a self-run result in cycle-accurate simulation, not an EEMBC-certified
score. Run it with `make coremark COREMARK_DIR=path/to/coremark`.

## Two real CPU bugs that only DOOM found

All the official tests and thousands of random programs passed, and the CPU was
still wrong. Doom exposed two pipeline hazards, which were then turned into
directed tests that fail on the old RTL:

1. **Store during a load-use stall.** A store held in EX by a stall still sent
   its memory access with a not-yet-forwarded address and wrote a random
   location. In Doom this corrupted libc's character table.
   Fix: gate memory access with `!stall`. Test: `tests/t14_ldst_stall.S`.
2. **Forwarded operands lost during a stall.** `lw s6; lw a5; blt a5,s6`: the
   value of `s6`, forwarded from writeback, was gone by the time the stall
   ended, so the branch compared a stale register. In Doom: "bad texture
   directory" and striped frames. Fix: latch the forwarded operands.
   Test: `tests/t15_ld_ld_br.S`.

## Quick start

### Requirements

Tested on Ubuntu 24.04:

```sh
sudo apt install verilator yosys nextpnr-ice40 fpga-icestorm \
  gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf libsdl2-dev python3 make
```

Versions used: Verilator 5.020, Yosys 0.33, nextpnr 0.6, riscv64-unknown-elf-gcc
13.2, picolibc 1.8.6, SDL 2.30. SymbiYosys + z3 are only needed for the formal
check.

External files (not in this repo), passed in as Make variables:

```sh
git clone https://github.com/riscv-software-src/riscv-tests   # official tests
git clone https://github.com/eembc/coremark                     # CoreMark benchmark
# DOOM shareware WAD v1.9 (doom1.wad, sha1 5b2e249b9c5133ec987b3ea77596381dc0d6bc1d)
```

### Run

```sh
make test   RVTEST_DIR=path/to/riscv-tests/isa   # directed + official + random, prints ALL PASS
make all_tests RVTEST_DIR=... WAD_SRC=path/to/doom1.wad  # every suite incl. Doom
make coremark COREMARK_DIR=path/to/coremark  # CoreMark score
make doom   WAD_SRC=path/to/doom1.wad   # headless Doom, frames in build/doom/frames
make play   WAD_SRC=path/to/doom1.wad   # live SDL window with keyboard
make play_test WAD_SRC=...              # scripted play, must differ from a no-key run
make fpga_full FPGA_FREQ=13 FPGA_SEED=7 # synth + place & route for iCE40 UP5K
```

Controls in `make play`: arrows move, Ctrl fires, Space opens doors, Enter/Esc
for menus, 1–7 select weapons, `-` shrinks the view (faster).

## Repository layout

```text
rtl/        CPU in SystemVerilog (top_pipe.sv is the pipeline; *_fpga.sv are FPGA variants)
tb/         Verilator testbenches (C++ and SV), including the Doom play harness
tests/      15 directed assembly tests
iss/        Python reference instruction-set simulator
tools/      random program generator, trace compare, play-test verifier, helpers
formal/     SymbiYosys pipeline proof
programs/   small C benchmarks (fib, sort, matmul, ...)
bench/      CoreMark port (timer = mcycle, UART output)
doom/       Doom port: crt0, linker script, file layer, MMIO glue; doom/src = doomgeneric (vendored, upstream e257a09)
docs/       DESIGN.md (detailed design notes and numbers), Doom screenshots
PROMPT.md   the task specification the AI agent worked from
PROGRESS.md the agent's lab notebook: every milestone, bug, root cause and measurement
```

The detailed microarchitecture, verification approach, measured metrics and
optimization history are in [`docs/DESIGN.md`](docs/DESIGN.md).

## How it was built

- **The builder** is an open-weight coding model (Qwen 3.8 Flash Next Coder,
  125B parameters, 1.75-bit quantization) running locally on a PC with a 12 GB
  GPU and 32 GB RAM, driven by [opencode](https://opencode.ai) in a sandbox that
  could only run the HDL tools.
- **The rules** ([`PROMPT.md`](PROMPT.md)): every number must come from tool
  output, every testbench is self-checking, never edit a test to make it pass,
  a fresh-clone check before every commit, and a milestone list from
  "single-cycle RV32I" to "Doom runs".
- **Supervision:** a watchdog restarted the agent when it stalled, and a
  second, read-only reviewer agent audited each milestone. Claude (Anthropic)
  was used for setup, reviews and debugging: it found the stall-forwarding bug
  above, the keyboard timing bug in the play harness, and a play test that
  passed even with a dead keyboard.
- **Timeline:** first commit 2026-10-31 23:27, finished 2026-11-02 10:39
  (about 35 hours).

[`PROGRESS.md`](PROGRESS.md) keeps the full history, including the failed
attempts.

## Honest limits

- DOOM runs in **simulation**. The UP5K has 128 KB of RAM and Doom needs about
  8 MB, so the FPGA build proves the CPU fits and meets timing, but runs a small
  built-in program. A board with SDRAM is needed to play it on real hardware.
- Simulation speed peaked at 5.8M cycles/s; a 15M target was attempted and missed
  (attempts recorded in `PROGRESS.md`).
- No atomics (A), no supervisor/user mode, no MMU, so no Linux yet.
- The formal proof covers pipeline invariants, not full ISA equivalence.
- The FPGA build truncates the 64-bit counters to 32 bits.

## License

MIT for this project's own code, see [LICENSE](LICENSE). `doom/src` is
doomgeneric (GPL v2). DOOM is a trademark of id Software; the WAD is not
included.
