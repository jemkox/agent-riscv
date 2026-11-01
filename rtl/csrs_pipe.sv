// CSR pipeline helper: wraps CSRs, timer/trap flushes, and id-stage CSR read.
module csrs_pipe (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt,
  input  logic        idex_valid,
  input  logic [31:0] idex_insn,
  input  logic [31:0] idex_pc,
  input  logic        ce_sys,
  input  logic        ce_ill,
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
  output logic        idex_ld,
  output logic        idex_st,
  output logic        idex_trap,
  output logic        idex_stop,
  output logic        idex_csr_en,
  output logic        idex_csr_wen,
  output logic        trap_flush,
  output logic        timer_flush,
  output logic [31:0] idex_cs_old,
  output logic [31:0] cs_old,
  output logic [31:0] cs_mtvec,
  output logic        halt_out
);
  logic        trap_mode, timer_due, trap_en;
  logic [31:0] trap_pc, trap_cause;
  /* verilator lint_off UNUSED */
  logic [31:0] mc_next, mtcmp_next, mstatus_next;
  logic [31:0] cs_mstatus, cs_mepc, cs_mcause, cs_mcycle, cs_minstret, cs_mtimecmp;
  /* verilator lint_on UNUSED */

  csrs CSRS(.clk(clk), .reset(reset), .halt_in(halt),
            .trap_en(trap_en), .trap_pc(trap_pc), .trap_cause(trap_cause),
            .cs_read_en(exmem_valid && exmem_csr_en), .cs_rsel(exmem_insn[31:20]),
            .cs_old(cs_old),
            .cs_write_en(exmem_valid && exmem_csr_en && exmem_csr_wen),
            .cs_wsel(exmem_insn[31:20]), .cs_winsn(exmem_insn), .cs_wop(exmem_f3),
            .cs_wrs1(exmem_r1), .retire_en(exmem_valid && !halt && !reset),
            .idex_read_en(idex_valid && ce_csr), .idex_rsel(idex_insn[31:20]), .cs_old_idex(idex_cs_old),
            .mc_next(mc_next), .mtcmp_next(mtcmp_next), .mstatus_next(mstatus_next),
            .halt_out(halt_out),
            .mstatus(cs_mstatus), .mtvec(cs_mtvec), .mepc(cs_mepc),
            .mcause(cs_mcause), .mcycle(cs_mcycle), .minstret(cs_minstret), .mtimecmp(cs_mtimecmp));

  always_comb begin
    idex_ld = idex_valid && ld_ok;
    idex_st = idex_valid && st_ok;
    trap_mode = mstatus_next[11];
    idex_trap = idex_valid && (ce_sys || ce_ill) && trap_mode;
    idex_stop = idex_valid && (ce_sys || ce_ill) && !trap_mode;
    idex_csr_en = idex_valid && ce_csr;
    idex_csr_wen = idex_csr_en && ((ce_f3 == 3'b001) || (ce_f3 == 3'b101) ||
      ((ce_f3 == 3'b010 || ce_f3 == 3'b011) && ce_rs1 != 5'd0) ||
      ((ce_f3 == 3'b110 || ce_f3 == 3'b111) && idex_insn[19:15] != 5'd0));
    trap_pc = idex_pc;
    timer_due = idex_valid && trap_mode && (mc_next >= mtcmp_next) &&
                (idex_pc != cs_mtvec);
    if (idex_trap)
      trap_cause = (idex_insn == 32'h00100073) ? 32'd1 : (ce_sys ? 32'd0 : 32'd2);
    else if (timer_due) trap_cause = 32'h8000_0007;
    else trap_cause = 32'h0;
    trap_flush = idex_trap && !stall && !m_stall;
    timer_flush = timer_due && !stall && !m_stall && !trap_flush;
    trap_en = trap_flush || timer_flush;
  end
endmodule
