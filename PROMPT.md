TASK: Design, verify, synthesize and benchmark a RISC-V CPU in SystemVerilog, working fully autonomously for as long as it takes (hours is expected). Project folder: ~/agent-workspace/hdl/rv32cpu

## TASK-SPECIFIC OVERRIDES (these take priority for this task)
- A failing simulation, failing test, lint error or failed timing is NOT a "failed tool call". It is normal work: read the output, fix the design, rerun. The "stop after two failures" rule applies only when a command itself is malformed or the tool is broken.
- Do NOT stop, ask me questions or give a final answer until FINAL ACCEPTANCE is proven by output you saw. If stuck, debug harder: add $display traces, write smaller unit tests, bisect.
- Instead of the 4-line note, write ONE short line before each batch of actions (e.g. "Fixing load-use stall in hazard unit, rerunning regression").

## HOW TO RUN THINGS (or you will be blocked waiting for approval)
- Run ALL tools through the wrapper: `hdl make <target>` (preferred), `hdl iverilog -g2012 ...`, `hdl vvp ...`, `hdl verilator ...`, `hdl yosys ...`, `hdl nextpnr-ice40 ...`, `hdl icepack ...`, `hdl icetime ...`, `hdl riscv64-unknown-elf-gcc ...`. Never call them directly.
- python3 scripts may be run directly: `python3 iss/iss.py ...`
- NEVER use redirection (>, >>, 2>&1, 2>/dev/null) or $( ) or tee or xargs in commands. To save output to files: testbenches use $fopen/$fdisplay, Python scripts open and write files themselves, and the Makefile may redirect internally (it runs inside `hdl make`). Piping into `| head` or `| tail` is fine.
- Do not try to clone or download anything. Write all tests and benchmarks yourself.
- Your output per message is limited: keep every file under ~250 lines. Split big designs into many small modules and files. Edit files with small targeted edits instead of rewriting them.

## TOOLS (all installed and working)
- Icarus Verilog (iverilog/vvp): quick unit tests.
- Verilator with full simulation (g++ is installed): `verilator --binary --timing -j 0 --top-module tb <files>` builds a fast simulator in obj_dir/. About 100x faster than Icarus: use it for the random regression and for running C programs. Build and run it from Makefile targets.
- Yosys: synthesis. `yosys -p 'synth_ice40 -top <top> -json build/cpu.json' <files>` and `yosys -p 'synth -top <top>; stat' <files>` for cell counts.
- nextpnr-ice40 + IceStorm: real place-and-route and timing for a Lattice iCE40 UP5K FPGA: `nextpnr-ice40 --up5k --package sg48 --json build/cpu.json --asc build/cpu.asc --freq 30` (read "Max frequency" in the output), then `icepack build/cpu.asc build/cpu.bin`.
- RISC-V toolchain: riscv64-unknown-elf-gcc/as/objcopy/objdump with picolibc. Use -march=rv32im -mabi=ilp32 (add _zicsr where needed), `--specs=picolibc.specs` for C programs with a libc, -nostartfiles with your own crt0.S and linker script for bare metal.

## EXTRA VERIFICATION TOOLS (installed later; use them)
- QEMU reference CPU: `hdl qemu-riscv32 prog.elf` runs a Linux-ABI static RV32 ELF on a known-correct CPU; `-d in_asm,cpu -D trace.log` dumps an instruction/register trace. Use it to cross-check your Python ISS (run the same programs on both; any disagreement means the ISS is wrong) and as a second golden model for C programs.
- Official tests: ~/agent-workspace/downloads/riscv-tests (isa/rv32ui, rv32um, rv32mi + env/ macros) and ~/agent-workspace/downloads/riscv-arch-test (tests/rv32i/I, M, Zicsr...). Copy into tests/official/, write a small env/linker script for your testbench (pass/fail via a tohost-style store the testbench watches), and add them to `make test`. From M2 on, every rv32ui test must pass; from M3, every rv32um test.
- Formal: `hdl sby -f job.sby` with engine `smtbmc z3` (never boolector). After M2, add assertions (x0 always reads 0, PC aligned, no write to x0, stall/flush never both drop an instruction) and prove them. riscv-formal is in ~/agent-workspace/downloads/riscv-formal if you want to try the full RVFI check later.
- ccache makes Verilator rebuilds fast. SDL2 is available for a framebuffer window (stretch goals).

## WORK LOOP
PLAN → WRITE HDL → LINT → SIMULATE → SYNTHESIZE → READ OUTPUT → FIX → REPEAT.
- METRICS must be measured: every number in the PROGRESS.md METRICS table (IPC, cycles, cells/LUTs, Fmax, misprediction rate, benchmark score) must come from tool output you actually saw (the testbench #SUMMARY line, Yosys stat, nextpnr, ...). If you cannot measure it yet, write `not measured`, never an estimate.
- FRESH-CLONE CHECK before every commit: `rm -rf ../rv32cpu-check && git clone -q . ../rv32cpu-check && cd ../rv32cpu-check && hdl make test` (stay inside ~/agent-workspace so `hdl` works). It must pass there too. This catches absolute paths, files you forgot to commit and leftovers from your build folder. Never hard-code /home/... paths in RTL, testbenches, scripts or the Makefile; use paths relative to the project folder (the official test suites in ~/agent-workspace/downloads may be referenced through one Makefile variable).
- Keep PROGRESS.md: what works, what failed, root cause, next step, and a METRICS table (milestone, tests passed, IPC, cells/LUTs, Fmax). Update it after every milestone and every major bug. If you lose context, read PROGRESS.md first and continue.
- git commit after each passing milestone so you can always roll back.
- Every testbench is self-checking and ends with exactly `TEST PASSED` or `TEST FAILED: <n> errors`.
- Never edit tests or the reference model to make them pass. Never hard-code expected results. Never claim a pass you did not see.
- Synthesizable RTL only: no # delays or initial blocks in RTL (use $readmemh for memory init), <= in clocked blocks, always_comb with defaults, defined reset. Zero `verilator --lint-only -Wall` warnings.
- At EVERY milestone, run Yosys synthesis of the core (without testbench memories, or with memories inferred as block RAM). It must synthesize with no latches and no errors. Record the cell/LUT count.

## VERIFICATION (this is what makes the CPU real)
- Write a Python reference instruction-set simulator (ISS) for RV32IM (+ Zicsr later).
- Assemble test programs with riscv64-unknown-elf-gcc/as and convert to hex for $readmemh with objcopy (Makefile target).
- Differential testing: the RTL testbench writes every retired instruction (PC, instr, rd, value) to a log via $fdisplay. The ISS writes the same log for the same program. A Python script compares them and reports the first mismatch.
- Random program generator (valid RV32IM, safe memory region, bounded loops/branches). Run thousands through the differential test using the Verilator simulator. Fix every mismatch.
- Directed tests for every instruction and corner case: x0 writes, signed/unsigned compares, shift amounts, DIV by zero, INT_MIN / -1, back-to-back load-use, branch after load.

## MILESTONES (finish each completely, regression passing, synthesis clean, git commit, before the next)
M1: Single-cycle RV32I + Python ISS + differential harness. All directed tests pass. Yosys synthesis clean.
M2: 5-stage pipeline (IF/ID/EX/MEM/WB), full forwarding, load-use stall, branch flush. Switch the regression to Verilator. 5000+ random programs, 0 mismatches.
M3: M extension, multi-cycle divider with correct stall.
M4: Branch predictor (BTB + 2-bit counters or gshare). Measure and report the real misprediction rate and IPC before/after.
M5: Zicsr + machine mode: mcycle, minstret, mstatus, mtvec, mepc, mcause, ecall, ebreak, illegal-instruction trap, timer interrupt. Directed test per trap.
M6: Instruction and data caches with a memory model of configurable latency; pipeline stalls correctly on misses. Regression passes with latency 1, 5 and 20.
M7: Memory-mapped UART at a fixed address that the testbench prints. crt0.S + linker script; compile and run in Verilator: hello world, recursive fibonacci, sort of 1000 numbers, matrix multiply (each self-checking), and a Dhrystone/CoreMark-style benchmark you write yourself. Report cycles, instructions, IPC from mcycle/minstret.
M8 FPGA: Make an FPGA top (cpu + block-RAM memory + UART TX pin) for iCE40 UP5K. Run yosys synth_ice40 → nextpnr-ice40 → icepack until it places, routes and produces build/cpu.bin. Report LUTs used (of 5280), BRAM used, and Max frequency. Then OPTIMIZE: find the critical path from the nextpnr report, improve it (retime, split logic, simplify forwarding/compare paths), and rerun. Keep a table of each optimization and its Fmax/LUT effect. Regression must still pass after every change.
M9 (stretch, in order, only after M8 is committed): dual-issue in-order superscalar; RV32C compressed; RV32A. Full regression + FPGA build after each; fix or revert if it breaks.

## M10: DOOM IN SIMULATION (new goal, after FINAL ACCEPTANCE)
FINAL ACCEPTANCE (M1-M8) is done; do not redo it. The new goal is to run the shareware Doom on THIS 5-stage
RV32IM CPU (rtl/top_pipe.sv) in Verilator simulation. Keep every existing test passing (`hdl make test`, `ui`, `um`,
`regress`, `m7`) after each step, and commit after each step below.
Inputs (already downloaded, read-only - copy what you need into the project):
- Doom source: ~/agent-workspace/downloads/doomgeneric (port layer: implement doomgeneric_rv32.c with DG_Init,
  DG_DrawFrame, DG_SleepMs, DG_GetTicksMs, DG_GetKey, DG_SetWindowTitle; see doomgeneric_xlib.c for an example).
- Game data: ~/agent-workspace/downloads/doomwad/doom1.wad (shareware v1.9, 4,196,020 bytes).
- C library: picolibc (`--specs=picolibc.specs`); provide the few syscalls Doom needs (memory allocation via a
  heap in RAM, file access served from the WAD loaded into memory, output to the UART).
Steps:
M10a Fast multiplier: make MUL/MULH/MULHSU/MULHU take at most 4 cycles (divide may stay iterative). Doom multiplies
     a lot. Measure the new IPC on matmul and the official UM tests.
M10b Big memory: a Doom testbench (e.g. tb/run_doom.sv or a Verilator C++ main) with at least 16 MB of RAM that loads
     the program and doom1.wad into memory before reset. Use a simple flat memory for this testbench if the cache
     latency model is too slow or too small; the CPU core must stay rtl/top_pipe.sv.
M10c Devices (memory-mapped, documented in README): a 320x200 framebuffer with an 8-bit palette (or 32-bit pixels),
     a "frame done" register, a key register, and timing from mcycle/mtime at an assumed 50 MHz clock.
     The testbench writes frames as image files (PNG via a small Python script, or PPM) into build/doom/frames/.
     Optional: an SDL2 window in a Verilator C++ main (SDL2 is installed) to watch it live.
M10d Port and run: build Doom with riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -O2. Run with no input so Doom
     plays its built-in attract-mode demo. Success = the title screen and at least 30 consecutive in-game demo frames
     are rendered correctly as images (check them; do not claim success from a log line alone).
M10e Results: record measured cycles per frame, the frame rate at the assumed 50 MHz, and the simulation wall-clock
     speed (frames per real second) in PROGRESS.md and README. Put 3 sample frames in docs/doom/ and, if possible,
     an animated GIF of the demo (ffmpeg is NOT installed; use Python if you make a GIF).
When M10d and M10e are done and proven with real frame images, write the line `M10 DOOM: MET` in PROGRESS.md and stop.

## FINAL ACCEPTANCE (only then may you stop)
- `hdl make test` runs the whole regression from scratch (directed, random differential, official rv32ui + rv32um tests) and prints ALL PASS. Show that output.
- 5000+ random differential tests: 0 mismatches.
- M7 programs print correct results over UART.
- `hdl make fpga` produces build/cpu.bin and prints LUTs and Max frequency.
- README.md: ASCII block diagram, microarchitecture, ISA supported, measured IPC, branch prediction accuracy, benchmark score, LUTs, Fmax on iCE40 UP5K, optimization history, how to run, honest known limitations.

START NOW. If the project folder already has work in it, read PROGRESS.md and the existing files first and continue from there instead of starting over. Do not reply with a plan. Execute.
