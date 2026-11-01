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