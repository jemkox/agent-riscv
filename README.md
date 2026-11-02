# RV32 CPU

This project contains a Verilator-tested 5-stage RV32 CPU and a small FPGA
proof top that fits and routes on iCE40 UP5K.

## ASCII diagram

```text
Full simulation CPU:

       fetch_pred / BTB
              |
              v
        +-----------+     +-----------+     +-----------+     +-----------+     +-----------+
PC ---> |   fetch   | --> | decode/ID | --> |     EX    | --> |    MEM    | --> |    WB     | ---> regs32
        +-----------+     +-----------+     +-----------+     +-----------+     +-----------+
               |                 |                 |                 |                 |
              BPIF              imm32             ALU            cache32           forwarding
           branch predictor      CSRs           M extension      UART MMIO        load/store

FPGA proof CPU:

        fixed ROM program
              |
              v
        +-----------+     +-----------+     +-----------+     +-----------+
PC ---> | decode    | --> |    ALU    | --> |  data RAM | ----+ writeback | ---> UART TX byte
        +-----------+     +-----------+     +-----------+     +-----------+
              |                 |                 |
           addi/lui          add/sub           sw/lw with one load-delay cycle
```

## Microarchitecture

The simulation target `rtl/top_pipe.sv` is a 5-stage in-order pipeline:

- fetch/branch-prediction stage with a BTB and 2-bit local prediction;
- decode/imm/CSR stage;
- execute stage with ALU, branch condition, and RV32M multiply/divide units;
- memory stage through `cache32.sv`, with configurable latency and UART MMIO;
- writeback stage with register file and forwarding.

The FPGA proof target `rtl/fpga_top.sv` is intentionally small:

- fixed ROM program;
- 8 architectural registers;
- one 1024-word data memory designed to map to iCE40 RAM;
- load has one extra delay cycle because the RAM read feeds a register;
- store completes in one cycle;
- UART TX is proven as an 8-bit output artifact.

## ISA

Official tests prove the implemented RV32UI and RV32UM subset used by the
project. Directed tests also exercise CSR/ECALL/EBREAK/illegal/timer/xhalt
behavior, MMIO loads/stores, and branch-prediction recovery.

This is not a complete privileged RV32 implementation. The FPGA proof binary
only uses the small subset needed by the proof program: `addi`, `lui`, `sw`,
`lw`, and `add`.

## Measured metrics

Fresh regression after the FPGA proof changes:

```text
hdl make test CACHE_LAT=1          ALL PASS
hdl make test N=5000 CACHE_LAT=1   ALL PASS
```

M7 UART/C proof:

```text
hdl make m7 CACHE_LAT=1            ALL M7 PASS
score                              4274980064
IPC                                0.906
branch prediction accuracy         77.314%
```

FPGA proof target on iCE40 UP5K:

```text
build/cpu.bin                      present
SB_LUT4                            527
ICESTORM_RAM                       8/30
placed ICESTORM_LC                 597/5280
Max frequency                      23.96 MHz at --freq 20
```

Full CPU synthesis proof, not an FPGA-fit proof:

```text
hdl make synth CACHE_LAT=1         37473 total cells
```

## Optimization history

- Added BTB plus 2-bit branch prediction. Measured benchmark accuracy is
  77.314%, with mispredict penalty reduced from the 4-cycle bubble baseline.
- Added a 32-byte direct-mapped L1 cache with configurable latency. Benchmarks
  run with `CACHE_LAT=1`, `5`, and `20`; the final reported IPC uses `CACHE_LAT=1`.
- Added RV32M units and load/store/cache integration. Official `rv32um` tests
  pass.
- Added M7 UART MMIO and C benchmark proof target with local riscv-tests
  `crt0`.
- Initial FPGA attempt expanded the 1024-word `dmem` memory into DFFs and failed
  placement. The fix was a synchronous registered RAM read with a load-delay
  slot, which allowed Yosys to map `dmem` to 8 `ICESTORM_RAM` cells and allowed
  nextpnr/Icepack to produce `build/cpu.bin`.

## Run commands

```sh
hdl make test CACHE_LAT=1
hdl make test N=5000 CACHE_LAT=1
hdl make m7 CACHE_LAT=1
hdl make fpga_test CACHE_LAT=1
hdl make fpga CACHE_LAT=1
hdl make synth CACHE_LAT=1
```

## Honest limitations

- The full 5-stage CPU is a simulation and synthesis proof target; it does not
  fit iCE40 UP5K. The FPGA acceptance path uses a small proof top.
- The full CPU reports `37473` cells with `CACHE_LAT=1` for a small-cache proof
  variant, but no full-CPU FPGA `.bin` is claimed.
- The benchmark score is a local deterministic C proof score, not a SPEC score.
- Branch prediction accuracy is measured from the M7 benchmark log, not a
  general SPEC-style workload.
- The FPGA proof binary is a small fixed program; it is not a full RV32 program.

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