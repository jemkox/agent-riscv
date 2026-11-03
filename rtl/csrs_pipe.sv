// CSR pipeline helper: wraps CSRs + CLINT, trap/interrupt/mret flushes, id CSR read.
module csrs_pipe (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt,
  input  logic        idex_valid,
  input  logic [31:0] idex_insn,
  input  logic [31:0] idex_pc,
  input  logic        ce_sys,
  input  logic        ce_ill,
  input  logic        ce_fetch_bad,
  input  logic        ce_mret,
  input  logic        ce_csr,
  input  logic [2:0]  ce_f3,
  input  logic [4:0]  ce_rs1,
  input  logic        ld_ok,
  input  logic        st_ok,
  input  logic        stall,
  input  logic        m_stall,
  input  logic        exmem_valid,
  input  logic        exmem_csr_en,
  input  logic        exmem_csr_wen,
  input  logic [31:0] exmem_insn,
  input  logic [2:0]  exmem_f3,
  input  logic [31:0] exmem_r1,
  input  logic [31:0] idex_ea,
  input  logic [31:0] idex_sd_raw,
  input  logic        clint_commit,
  output logic        idex_ld,
  output logic        idex_st,
  output logic        idex_trap,
  output logic        idex_stop,
  output logic        idex_csr_en,
  output logic        idex_csr_wen,
  output logic        trap_flush,
  output logic        timer_flush,
  output logic        mret_flush,
  output logic [31:0] mret_pc,
  output logic [31:0] idex_cs_old,
  output logic [31:0] cs_old,
  output logic [31:0] cs_mtvec,
  output logic        halt_out,
  output logic [31:0] clint_ld_data,
  output logic        irq_pending
);
  logic        trap_en, mret_active, mret_en, irq_due;
  logic [31:0] trap_cause, irq_cause;
  logic [31:0] mstatus_next, mie_next, mtvec_next, mepc_next;
  logic [31:0] insn_cause;
`ifndef FPGA
  logic [31:0] clint_mip;
`endif

  csrs CSRS(.clk(clk), .reset(reset), .halt_in(halt),
            .trap_en(trap_en), .trap_pc(idex_pc), .trap_cause(trap_cause),
            .mret_en(mret_en),
            .cs_read_en(exmem_valid && exmem_csr_en), .cs_rsel(exmem_insn[31:20]),
            .cs_old(cs_old),
            .cs_write_en(exmem_valid && exmem_csr_en && exmem_csr_wen),
            .cs_wsel(exmem_insn[31:20]), .cs_winsn(exmem_insn), .cs_wop(exmem_f3),
            .cs_wrs1(exmem_r1), .retire_en(exmem_valid && !halt && !reset),
            .idex_read_en(idex_valid && ce_csr), .idex_rsel(idex_insn[31:20]), .cs_old_idex(idex_cs_old),
`ifndef FPGA
            .mip_in(clint_mip),
`endif
            .mstatus_next(mstatus_next), .mie_next(mie_next), .mtvec_next(mtvec_next),
            .mepc_next(mepc_next), .halt_out(halt_out));

  clint_dev CL(.clk(clk), .reset(reset), .halt_in(halt),
            .retire_en(exmem_valid && !halt && !reset),
            .commit(clint_commit), .ea(idex_ea), .wdata(idex_sd_raw),
            .mstatus_in(mstatus_next), .mie_in(mie_next),
            .ld_data(clint_ld_data), .pending(irq_pending), .cause(irq_cause)
`ifndef FPGA
            ,.mip_out(clint_mip)
`endif
            );

  always_comb begin
    idex_ld = idex_valid && ld_ok;
    idex_st = idex_valid && st_ok;
    // Standard model: synchronous traps are always enabled (mtvec set by software).
    idex_trap = idex_valid && (ce_sys || ce_ill || ce_fetch_bad);
    idex_stop = 1'b0;
    idex_csr_en = idex_valid && ce_csr;
    idex_csr_wen = idex_csr_en && ((ce_f3 == 3'b001) || (ce_f3 == 3'b101) ||
      ((ce_f3 == 3'b010 || ce_f3 == 3'b011) && ce_rs1 != 5'd0) ||
      ((ce_f3 == 3'b110 || ce_f3 == 3'b111) && idex_insn[19:15] != 5'd0));
    if (idex_insn == 32'h0010_0073)      insn_cause = 32'd3;           // EBREAK
    else if (idex_insn == 32'h0000_0073) insn_cause = 32'd11;          // ECALL (machine)
    else if (ce_fetch_bad)               insn_cause = 32'd0;           // misaligned fetch
    else                                 insn_cause = 32'd2;           // illegal
    irq_due = idex_valid && irq_pending;
    mret_active = idex_valid && ce_mret && !stall && !m_stall && !irq_due;
    trap_flush = idex_trap && !stall && !m_stall;
    // synchronous exception has priority over a pending interrupt (spec).
    timer_flush = irq_due && !stall && !m_stall && !trap_flush;
    trap_en = trap_flush || timer_flush;
    trap_cause = trap_flush ? insn_cause : irq_cause;
    mret_en = mret_active && !trap_flush && !timer_flush;
    mret_flush = mret_en;
    mret_pc = mepc_next;   // a csrw mepc right before the mret must count
    cs_mtvec = mtvec_next; // mtvec write retiring this cycle is visible
  end
endmodule
