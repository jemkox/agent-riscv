# HDL Notes

## Current design
- `rtl/top_pipe.sv`: five-stage pipeline top for RV32I.
- `rtl/top_single.sv`: retained single-cycle reference for synthesis proof.
- `rtl/ctrl.sv`, `rtl/imm32.sv`, `rtl/alu.sv`, `rtl/regs32.sv`, `rtl/mem32.sv`: common decoder, immediate, ALU, register, and memory modules.

## Pipeline design points
- Five pipeline stages: IF/ID, ID/EX, EX/MEM, MEM/WB.
- Operands are latched into ID/EX with forwarding from current EX/MEM and MEM/WB.
- Current ID/EX ALU operands are forwarded again from EX/MEM/MEM/WB for distance-1 hazards.
- Load-use hazards stall the dependent instruction when a load is in EX/MEM.
- Branch/JAL/JALR flushes discard the wrong-path `IF/ID` instruction and set PC to target.
- Fetch/store address conflicts suppress the same-address fetch until the store writes.
- `rv_valid = mwb_valid && !reset` gates the retire log for Verilator/Icarus runners.

## Last test result
- `hdl make test`: directed tests passed, `ALL PASS`.
- `hdl make regress N=200`: Verilator differential regression passed, `ALL PASS`.
- `hdl make ui`: official `rv32ui` tests passed, `ALL UI PASS`.
- `hdl make lint`: pipeline lint passed with no errors.