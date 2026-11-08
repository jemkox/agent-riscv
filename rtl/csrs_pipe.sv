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
  input  logic        ce_sret,
  input  logic        ce_csr,
  input  logic [1:0]  ce_csr_req,    // required privilege of the id CSR op
  input  logic        ce_csr_def,    // CSR number implemented; when 0 the CSR op faults
  input  logic        ce_csr_ro,     // read-only CSR number (write attempt faults)
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
  input  logic [31:0] exmem_pc,
  input  logic [2:0]  exmem_f3,
  input  logic [31:0] exmem_r1,
  input  logic [31:0] idex_ea,
  input  logic [31:0] idex_sd_raw,
`ifndef FPGA
  input  logic        dpf,           // data page fault at EX (L6 MMU)
  input  logic [3:0]  dpf_cause,     // 13/15
  input  logic        itpf,          // EX insn is an injected IT page fault
`endif
  input  logic        clint_commit,
  input  logic        wfi_tick,
  output logic        idex_ld,
  output logic        idex_st,
  output logic        idex_trap,
  output logic        cs_sfence,     // SFENCE.VMA retiring (TLB flush pulse)
  output logic        idex_stop,
  output logic        idex_csr_en,
  output logic        idex_csr_wen,
  output logic        trap_flush,
  output logic        timer_flush,
  output logic        mret_flush,
  output logic        sret_flush,
  output logic [31:0] mret_pc,
  output logic [31:0] idex_cs_old,
  output logic [31:0] cs_old,
  output logic [31:0] cs_sepc,
  output logic [31:0] cs_trap_pc,
  output logic        halt_out,
  output logic        mmu_mode,      // satp Sv32 on (L6)
  output logic [21:0] mmu_ppn,       // satp PPN
  output logic        cs_satp_wr,    // satp write pulse (TLB flush)
  output logic [1:0]  cs_priv,       // current privilege (L6 MMU)
  output logic        mmu_sum,       // mstatus.SUM (L6)
  output logic        mmu_mxr,       // mstatus.MXR (L6)
  output logic [31:0] clint_ld_data,
  output logic        irq_pending,
  output logic        timer_ready
);
  logic        trap_en, mret_active, mret_en, sret_en, sret_active, irq_due, trap_to_sup, priv_viol;
  logic [31:0] trap_cause, irq_cause;
  logic [1:0]  priv_cur;
  logic        csr_watt;   // id-view CSR op attempts a write (rs1/uimm nonzero)
  assign csr_watt = (ce_f3 == 3'b001) || (ce_f3 == 3'b101) ||
                    ((ce_f3 == 3'b010 || ce_f3 == 3'b011) && ce_rs1 != 5'd0) ||
                    ((ce_f3 == 3'b110 || ce_f3 == 3'b111) && idex_insn[19:15] != 5'd0);
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] mstatus_next, mie_next, mtvec_next, mepc_next, stvec_next, sepc_next;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] cs_medeleg, cs_mideleg;
  logic dpf_g, itpf_g; logic [3:0] dpc_g;
  logic [31:0] insn_cause;
  logic [31:0] insn_tval, trap_tval;
  logic [31:0] brimm, jimm;
`ifndef FPGA
  logic [31:0] clint_mip;
  logic [31:0] mip_sw_next;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] clint_mt, clint_cmp;
  /* verilator lint_on UNUSEDSIGNAL */
`endif

  csrs CSRS(.clk(clk), .reset(reset), .halt_in(halt),
            .trap_en(trap_en), .trap_to_sup(trap_to_sup), .trap_pc(idex_pc), .trap_cause(trap_cause),
            .trap_tval(trap_tval),
            .mret_en(mret_en), .sret_en(sret_en),
            .cs_read_en(exmem_valid && exmem_csr_en), .cs_rsel(exmem_insn[31:20]),
            .cs_old(cs_old),
            .cs_write_en(exmem_valid && exmem_csr_en && exmem_csr_wen),
            .cs_wsel(exmem_insn[31:20]), .cs_winsn(exmem_insn), .cs_wop(exmem_f3),
            .cs_wrs1(exmem_r1), .cs_pc(exmem_pc), .retire_en(exmem_valid && !halt && !reset),
            .idex_read_en(idex_valid && ce_csr), .idex_rsel(idex_insn[31:20]), .cs_old_idex(idex_cs_old),
`ifndef FPGA
            .mip_in(clint_mip),
`endif
            .mstatus_next(mstatus_next), .mie_next(mie_next), .mtvec_next(mtvec_next),
            .mepc_next(mepc_next), .stvec_next(stvec_next), .sepc_next(sepc_next),
            .priv_cur(priv_cur), .cs_medeleg(cs_medeleg), .cs_mideleg(cs_mideleg), .halt_out(halt_out),
            .mmu_mode(mmu_mode), .mmu_ppn(mmu_ppn), .cs_satp_wr(cs_satp_wr)
`ifndef FPGA
            , .cs_mip_sw(mip_sw_next), .cs_time_mt64(clint_mt)
`else
            , .cs_time_mt64(64'b0)
`endif
            );

  clint_dev CL(.clk(clk), .reset(reset), .halt_in(halt),
            .retire_en((exmem_valid && !halt && !reset) || wfi_tick),
            .commit(clint_commit), .ea(idex_ea), .wdata(idex_sd_raw),
            .mstatus_in(mstatus_next), .mie_in(mie_next), .mideleg_in(cs_mideleg), .priv_cur(priv_cur),
            .ld_data(clint_ld_data), .pending(irq_pending), .timer_ready(timer_ready), .cause(irq_cause)
`ifndef FPGA
            ,.mip_out(clint_mip)
            ,.mt_out(clint_mt)
            ,.cmp_out(clint_cmp)
            ,.mip_sw_in(mip_sw_next)
`endif
            );

  assign cs_priv = priv_cur;
  assign mmu_sum = mstatus_next[18];
  assign mmu_mxr = mstatus_next[19];
`ifdef FPGA
  assign dpf_g = 0; assign itpf_g = 0; assign dpc_g = 0;
  assign cs_sfence = 0;
`else
  assign dpf_g = dpf; assign itpf_g = itpf; assign dpc_g = dpf_cause;
  assign cs_sfence = idex_valid && (idex_insn[31:25] == 7'b0001001) &&
                     (idex_insn[11:7] == 5'b0) && !priv_viol;
`endif
  always_comb begin
    idex_ld = idex_valid && ld_ok && !dpf_g;
    idex_st = idex_valid && st_ok && !dpf_g;
    // Privilege checks: a CSR/mret/sret whose required privilege exceeds the
    // current mode faults as an illegal instruction instead of executing.
    priv_viol = idex_valid && ((ce_mret && (priv_cur != 2'b11)) ||
                              (ce_sret && (priv_cur == 2'b00 ||
                               (priv_cur == 2'b01 && ((mstatus_next & 32'h0040_0000) != 0)))) ||
                              (ce_csr && (priv_cur < ce_csr_req)) ||
                              (ce_csr && !ce_csr_def) ||
                              (ce_csr && ce_csr_ro && csr_watt) ||
                              // SFENCE.VMA: illegal in U; illegal in S when mstatus.TVM (rv32 bit20).
                              ((idex_insn[31:25] == 7'b0001001) && (idex_insn[11:7] == 5'b0) &&
                               (priv_cur == 2'b00 ||
                                (priv_cur == 2'b01 && ((mstatus_next & 32'h0010_0000) != 0)))) ||
                              // satp access in S is illegal when mstatus.TVM (U already covered).
                              (ce_csr && (idex_insn[31:20] == 12'h180) &&
                               (priv_cur == 2'b01) && ((mstatus_next & 32'h0010_0000) != 0)));
    // Standard model: synchronous traps are always enabled (mtvec set by software).
    idex_trap = idex_valid && (ce_sys || ce_ill || ce_fetch_bad || priv_viol || dpf_g || itpf_g);
    idex_stop = 1'b0;
    idex_csr_en = idex_valid && ce_csr && !priv_viol;
    idex_csr_wen = idex_csr_en && ((ce_f3 == 3'b001) || (ce_f3 == 3'b101) ||
      ((ce_f3 == 3'b010 || ce_f3 == 3'b011) && ce_rs1 != 5'd0) ||
      ((ce_f3 == 3'b110 || ce_f3 == 3'b111) && idex_insn[19:15] != 5'd0));
    if (itpf_g)                          insn_cause = 32'd12;          // IT page fault
    else if (dpf_g)                      insn_cause = {28'b0, dpc_g};  // 13/15
    else if (idex_insn == 32'h0010_0073) insn_cause = 32'd3;           // EBREAK
    else if (idex_insn == 32'h0000_0073) insn_cause = 32'h8 | {30'b0, priv_cur}; // ECALL: M 11, S 9, U 8
    else if (ce_fetch_bad)               insn_cause = 32'd0;           // misaligned fetch
    else                                 insn_cause = 32'd2;           // illegal
    irq_due = idex_valid && irq_pending;
    mret_active = idex_valid && ce_mret && !stall && !m_stall && !irq_due;
    sret_active = idex_valid && ce_sret && !stall && !m_stall && !irq_due;
    trap_flush = idex_trap && !stall && !m_stall;
    // synchronous exception has priority over a pending interrupt (spec).
    timer_flush = irq_due && !stall && !m_stall && !trap_flush;
    trap_en = trap_flush || timer_flush;
    trap_cause = trap_flush ? insn_cause : irq_cause;
    // medeleg/mideleg route U/S-mode traps to the supervisor handler.
    trap_to_sup = (priv_cur != 2'b11) && (trap_flush
        ? ((((cs_medeleg >> insn_cause[4:0]) & 32'h1) != 0) ? 1'b1 : 1'b0)
        : ((((cs_mideleg >> irq_cause[4:0]) & 32'h1) != 0) ? 1'b1 : 1'b0));
    // Vector mtvec/stvec low bit adds cause*4 to the aligned base.
    cs_trap_pc = ((trap_to_sup ? stvec_next : mtvec_next) & 32'hFFFF_FFFE) |
                 ((((trap_to_sup ? stvec_next : mtvec_next) & 32'h1) != 0)
                  ? ((trap_cause & 32'h1f) << 2) : 32'h0);
    // mtval/stval per cause: misaligned fetch reports the faulting target address,
    // EBREAK reports its address, illegal instructions report the encoding.
    brimm = {{20{idex_insn[31]}}, idex_insn[7], idex_insn[30:25], idex_insn[11:8], 1'b0};
    jimm  = {{11{idex_insn[31]}}, idex_insn[31], idex_insn[19:12], idex_insn[20], idex_insn[30:21], 1'b0};
    if (itpf_g)         insn_tval = idex_pc;                // IT PF: faulting fetch VA
    else if (dpf_g)       insn_tval = idex_ea;                // DPF: EA
    else if (ce_fetch_bad) insn_tval = (idex_insn[6:2] == 5'b11011) ? (idex_pc + jimm)
                          : ((idex_insn[6:2] == 5'b11000) ? (idex_pc + brimm)
                             : (idex_ea & 32'hFFFF_FFFE));
    else if (ce_sys)      insn_tval = (idex_insn == 32'h0010_0073) ? idex_pc : 32'h0;
    else                  insn_tval = idex_insn;
    trap_tval = trap_flush ? insn_tval : 32'h0;
    mret_en = mret_active && !trap_flush && !timer_flush;
    sret_en = sret_active && !trap_flush && !timer_flush;
    mret_flush = mret_en;
    sret_flush = sret_en;
    mret_pc = mepc_next;   // a csrw mepc right before the mret must count
    cs_sepc = sepc_next;   // sepc write retiring this cycle is visible to sret
    // mtvec_next is consumed by cs_trap_pc below.
  end
`ifdef LINUX_DEBUG
  logic [63:0] dbg_ret = 64'h0;
  always_ff @(posedge clk) begin
    if (!reset && (exmem_valid && !halt)) dbg_ret <= dbg_ret + 64'h1;
  end
  always_comb begin
    if (timer_flush)
      $display("DBG TIMERFLUSH pc=%08x cause=%08x mepc? mstat=%08x mip=%08x mt=%016x cmp=%016x ret=%016x",
               idex_pc, irq_cause, mstatus_next, clint_mip, clint_mt, clint_cmp, dbg_ret);
    if (mret_flush)
      $display("DBG MRETFLUSH pc=%08x mstat=%08x mepc=%08x mt=%016x cmp=%016x mip=%08x ret=%016x",
               idex_pc, mstatus_next, mepc_next, clint_mt, clint_cmp, clint_mip, dbg_ret);
    if (dbg_ret != 0 && dbg_ret[15:0] == 16'h0)
      $display("DBG MTICK mt=%016x ret=%016x cmp=%016x", clint_mt, dbg_ret, clint_cmp);
    if (idex_pc == 32'h8046bbdc)
      $display("DBG IRQHAND pc=%08x mstat=%08x mie=%08x mip=%08x mt=%016x cmp=%016x",
               idex_pc, mstatus_next, mie_next, clint_mip, clint_mt, clint_cmp);
    if (idex_pc == 32'h80298cc4)
      $display("DBG TIMERIRQ pc=%08x mstat=%08x mie=%08x mip=%08x mt=%016x cmp=%016x",
               idex_pc, mstatus_next, mie_next, clint_mip, clint_mt, clint_cmp);
    if (timer_flush && idex_pc >= 32'h80473db4 && idex_pc < 32'h80473f80)
      $display("DBG IRQINHAND pc=%08x mstat=%08x mie=%08x mip=%08x mt=%016x cmp=%016x",
               idex_pc, mstatus_next, mie_next, clint_mip, clint_mt, clint_cmp);
    if (trap_flush)
      $display("DBG TRAP pc=%08x insn=%08x cause=%08x mstat=%08x",
               idex_pc, idex_insn, insn_cause, mstatus_next);
  end
`endif
endmodule
