// 5-stage in-order RV32I pipeline: IF/ID/EX/MEM/WB.
// Retire output comes from MEM/WB; rv_valid gates retired instructions only.
module top_pipe (
  input  logic        clk,
  input  logic        reset,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd,
`ifdef DOOM_BIG
  input  logic        dbg_re,
  input  logic [31:0] dbg_ra,
  output logic [31:0] dbg_rd,
  // M10f: keyboard FIFO feed for DG_GetKey (see cache32 KEY_ADDR)
  input  logic [31:0] key_in,
  output logic        key_hit,
  // P3 counters (misses, M-unit stalls, load-use stalls)
  output logic [31:0] stat_icm,
  output logic [31:0] stat_dcm,
  output logic [31:0] mst_cnt,
  output logic [31:0] st_cnt,
`endif
`ifdef LINUX
  // Linux platform UART/initial a1. C++ runner drives RX and reads TX each cycle.
  input  logic [31:0] linux_dtb_addr,
  input  logic        uart_rx_ready,
  input  logic [7:0]  uart_rx_in,
  output logic        uart_tx_valid,
  output logic [7:0]  uart_tx_out,
  output logic        uart_rx_pending,
  output logic        uart_tx_ready,
`endif
  output logic        halt,
  output logic [31:0] ex_pc,
  output logic [31:0] ex_insn,
  output logic        ex_wben,
  output logic [4:0]  ex_rd,
  output logic [31:0] ex_wv,
  output logic        ex_st,
  output logic [31:0] ex_sa,
  output logic [31:0] ex_sd,
  output logic [3:0]  ex_sbe,
  output logic        rv_valid,
  output logic [31:0] bp_branches,
  output logic [31:0] bp_taken_preds,
  output logic [31:0] bp_mispreds
);
  logic [31:0] pc_if = 0;
  logic [31:0] ifid_pc = 0, ifid_insn = 0, idex_pc = 0, idex_insn = 0, idex_r1 = 0, idex_r2 = 0;
  logic [31:0] exmem_pc = 0, exmem_insn = 0, exmem_result = 0, exmem_wbval = 0, exmem_ea = 0,
               exmem_sd_log = 0;
  logic [31:0] mwb_pc = 0, mwb_insn = 0, mwb_sa = 0, mwb_sd = 0, mwb_wv = 0, exmem_ld_raw = 0;
  logic        fetch_ready, mem_ready;
  logic [4:0]  exmem_rd = 0, mwb_rd = 0, ce_rs1, ce_rs2, ce_rd, ceif_rs1, ceif_rs2;
  logic [31:0] a_ex, b_ex, aluB_ex, br_tgt_ex, iimm, simm, bimm, uimm, jimm, fetch_insn, rf_r1, rf_r2;
  logic [31:0] idex_ea, idex_sd_raw, idex_sd_log, idex_wbval, ldx_raw, ldx_ex, alu_res, md_result, exmem_r1 = 0;
  /* verilator lint_off UNUSED */
  logic [31:0] cs_old, cs_mtvec, idex_cs_old;
  logic [31:0] clint_ld;
  logic clint_commit, irq_pend, ce_wfi;
  logic ce_amo, ce_lr, ce_sc, amo_sc_ok, exmem_sc_ok;
  logic [4:0] ce_amo5;
  logic [31:0] amo_new, exmem_amo_new;
  logic exmem_is_amo, exmem_is_lr, exmem_is_sc, amo_log_wr;
  logic ceif_amo;
`ifdef FPGA
  logic idex_m_go;
`endif
`ifdef FPGA
  localparam ATOMIC = 0;   // atomics are Linux-only hardware; fold them out of the card
`else
  localparam ATOMIC = 1;
`endif
  /* verilator lint_on UNUSED */
  logic [3:0]  ce_alu_op, idex_sbe, idex_sbe_st, exmem_sbe = 0, mwb_sbe = 0;
  logic [1:0]  idex_ssz;
  logic [2:0]  ce_f3, exmem_f3 = 0, ce_m_op;
  logic        alu_eq, alu_slt_r, alu_slt_u, ld_ok, st_ok, idex_stop, idex_wben, idex_ld, idex_st;
  logic        stall, flush, conflict, flush_ex, m_stall, mem_pend, m_done_now, idex_m_done = 1'b1;
  logic        ifid_valid = 0, idex_valid = 0, exmem_valid = 0, mwb_valid = 0;
  logic        exmem_ld = 0, exmem_st = 0, exmem_stop = 0, exmem_wben = 0, mwb_st = 0, mwb_stop = 0, mwb_wben = 0;
  logic        read_a, read_b, ce_bsel, ce_ld, ce_st, ce_br, ce_jal, ce_jalr, ce_lui, ce_auipc, ce_opi, ce_op;
  logic        ce_sys, ce_fence, ce_ill, ce_m, ceif_ill, ceif_m, ce_csr, exmem_csr_en, exmem_csr_wen;
  logic        idex_csr_en, idex_csr_wen, idex_trap, trap_flush, timer_flush, halt_out, mret_flush, ce_mret;
  /* verilator lint_off UNUSEDSIGNAL */
  logic        amo_mmio_bad, ce_ex_ill;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] mret_pc;
  logic        ceif_ld, ceif_st, ceif_br, ceif_jalr, ceif_opi, ceif_op, ceif_csr;
  logic [31:0] ifid_r1_fwd, ifid_r2_fwd, idex_r1_cs;
  logic        bp_pred_if, branch_act_taken, branch_is, wrong_pred, bp_upd_enable, ifid_pred_taken = 0;
  logic        idex_pred_taken = 0;
  logic        idex_fetch_bad;
`ifdef DOOM_BIG
  // mst_cnt/st_cnt are output ports (declared in the header), incremented below.
`endif
`ifdef FPGA
  logic        rf_fetch_sched = 0;
  logic [4:0]  rf_rsel1 = 0, rf_rsel2 = 0;
  logic [31:0] rf_r1_use, rf_r2_use;
  assign rf_r1_use = rf_r1;
  assign rf_r2_use = rf_r2;
  assign rf_fetch_sched = !halt && !mem_pend && !(stall || m_stall) &&
                          !(trap_flush || timer_flush || mret_flush) &&
                          !flush && !conflict && fetch_ready;
  assign rf_rsel1 = rf_fetch_sched ? fetch_insn[19:15] : ifid_insn[19:15];
  assign rf_rsel2 = rf_fetch_sched ? fetch_insn[24:20] : ifid_insn[24:20];
`else
  logic [31:0] rf_r1_use, rf_r2_use;
  assign rf_r1_use = rf_r1;
  assign rf_r2_use = rf_r2;
`endif
  logic [31:0] ifid_pred_tgt = 0, idex_pred_tgt = 0, branch_upd_tgt, bp_pred_tgt_if;

`ifdef FPGA
  regs32 RF(.clk(clk), .reset(reset), .rsel1(rf_rsel1), .rsel2(rf_rsel2),
            .rs1(rf_r1), .rs2(rf_r2),
`ifdef LINUX
            .linux_init_valid(1'b1), .linux_init_addr(linux_dtb_addr),
`endif
            .wena(mwb_valid && mwb_wben && (mwb_rd != 5'd0) && !halt && !reset), .wsel(mwb_rd), .wdata(mwb_wv));
`else
  regs32 RF(.clk(clk), .reset(reset), .rsel1(ifid_insn[19:15]), .rsel2(ifid_insn[24:20]),
            .rs1(rf_r1), .rs2(rf_r2),
`ifdef LINUX
            .linux_init_valid(1'b1), .linux_init_addr(linux_dtb_addr),
`endif
            .wena(mwb_valid && mwb_wben && (mwb_rd != 5'd0) && !halt && !reset), .wsel(mwb_rd), .wdata(mwb_wv));
`endif
  cache32 MM(.clk(clk), .reset(reset), .halt(halt), .lwe(lwe), .lwa(lwa), .lwd(lwd),
`ifdef DOOM_BIG
             .dbg_re(dbg_re), .dbg_ra(dbg_ra), .dbg_rd(dbg_rd),
             .key_in(key_in), .key_hit(key_hit),
             .stat_icm(stat_icm), .stat_dcm(stat_dcm),
`endif
             .pc_if(pc_if), .fetch_insn(fetch_insn), .fetch_ready(fetch_ready),
             // No memory access while a load-use stall holds this instruction: its address/data operands
             // are not valid yet, and a store would write a wrong address (it is redone after the stall).
             .idex_valid(idex_valid && !stall), .idex_ld(idex_ld), .idex_st(idex_st),
             .ea(idex_ea), .sd_raw(idex_sd_raw), .ssz(idex_ssz),
`ifndef FPGA
             .amo_v(idex_valid && ce_amo && !ce_ex_ill && !stall),
             .amo_lr(ce_lr && idex_valid && !ce_ex_ill && !stall),
             .amo_sc(ce_sc && idex_valid && !ce_ex_ill && !stall), .amo5(ce_amo5),
             .amo_new(amo_new), .amo_sc_ok(amo_sc_ok),
`endif
             .ld_raw(ldx_raw), .mem_ready(mem_ready),
             .clint_commit(clint_commit), .clint_ld_in(clint_ld));
  /* verilator lint_off PINCONNECTEMPTY */
  ctrl   CE(.alu_op(ce_alu_op), .f3(ce_f3), .op7(), .rs1(ce_rs1), .rs2(ce_rs2), .rd(ce_rd),
            .a_sel(), .b_sel(ce_bsel), .is_ld(ce_ld), .is_st(ce_st), .is_br(ce_br),
            .is_jal(ce_jal), .is_jalr(ce_jalr), .is_lui(ce_lui), .is_auipc(ce_auipc),
            .is_opi(ce_opi), .is_op(ce_op),              .is_sys(ce_sys), .is_fence(ce_fence),
             .is_m(ce_m), .m_op(ce_m_op),              .is_mret(ce_mret), .is_ill(ce_ill),
             .is_csr(ce_csr), .csr_num(), .is_wfi(ce_wfi),
             .is_amo(ce_amo), .is_lr(ce_lr), .is_sc(ce_sc), .amo5(ce_amo5), .i(idex_insn));
`ifdef FPGA
  mdiu_fpga MD(.clk(clk), .reset(reset), .idex_valid(idex_valid), .is_m(idex_m_go), .is_ill(1'b0),
           .idex_done(idex_m_done), .op(ce_m_op), .a(a_ex), .b(b_ex), .ex_stall(stall),
           /* verilator lint_off PINCONNECTEMPTY */
           .md_active(), .md_done_now(m_done_now), .result(md_result));
           /* verilator lint_on PINCONNECTEMPTY */
`else
  mdiu_fast MD(.clk(clk), .reset(reset), .idex_valid(idex_valid), .is_m(ce_m), .is_ill(ce_ill),
           .idex_done(idex_m_done), .op(ce_m_op), .a(a_ex), .b(b_ex), .ex_stall(stall),
           /* verilator lint_off PINCONNECTEMPTY */
           .md_active(), .md_done_now(m_done_now), .result(md_result));
           /* verilator lint_on PINCONNECTEMPTY */
`endif
  /* verilator lint_on PINCONNECTEMPTY */
  /* verilator lint_off PINCONNECTEMPTY */
  ctrl   CEID(.alu_op(), .f3(), .op7(), .rs1(ceif_rs1), .rs2(ceif_rs2), .rd(),
              .a_sel(), .b_sel(), .is_ld(ceif_ld), .is_st(ceif_st),
              .is_br(ceif_br), .is_jal(), .is_jalr(ceif_jalr),
               .is_lui(), .is_auipc(), .is_opi(ceif_opi), .is_op(ceif_op),
               .is_sys(), .is_fence(), .is_m(ceif_m), .m_op(),
                .is_mret(), .is_ill(ceif_ill), .is_csr(ceif_csr), .is_wfi(),
                .is_amo(ceif_amo), .is_lr(), .is_sc(), .amo5(), .csr_num(), .i(ifid_insn));
  /* verilator lint_on PINCONNECTEMPTY */
  ldst  LDST(.is_ld(ce_ld), .is_st(ce_st), .is_amo(ce_amo), .is_ill(ce_ill), .ld_ok(ld_ok), .st_ok(st_ok));
  fwd   FWDD(.idex_valid(idex_valid), .ce_br(ce_br), .ce_jalr(ce_jalr), .ce_opi(ce_opi),
             .ce_op(ce_op), .ce_m(ce_m), .ce_csr(ce_csr), .ld_ok(ld_ok), .st_ok(st_ok),
`ifdef FPGA
             .ce_rs1(ce_rs1), .ce_rs2(ce_rs2),
`else
             .ce_amo(ce_amo), .ce_rs1(ce_rs1), .ce_rs2(ce_rs2),
`endif
             .idex_r1(idex_r1), .idex_r2(idex_r2),
             .exmem_valid(exmem_valid), .exmem_rd(exmem_rd), .exmem_wben(exmem_wben),
              .exmem_ld(exmem_ld), .exmem_st(exmem_st), .exmem_stop(exmem_stop),
              .exmem_result(exmem_result), .mwb_valid(mwb_valid), .mwb_rd(mwb_rd),
             .mwb_wben(mwb_wben), .mwb_wv(mwb_wv),
             .ifid_valid(ifid_valid), .ifid_r1(rf_r1_use), .ifid_r2(rf_r2_use),
             .ceif_br(ceif_br), .ceif_jalr(ceif_jalr), .ceif_ld(ceif_ld), .ceif_st(ceif_st),
`ifdef FPGA
`else
             .ceif_amo(ceif_amo),
`endif
              .ceif_opi(ceif_opi), .ceif_op(ceif_op), .ceif_m(ceif_m), .ceif_csr(ceif_csr), .ceif_rs1(ceif_rs1), .ceif_rs2(ceif_rs2),
             .a_ex(a_ex), .b_ex(b_ex), .read_a(read_a), .read_b(read_b),
             .ifid_r1_fwd(ifid_r1_fwd), .ifid_r2_fwd(ifid_r2_fwd));
  imm32  IM(.i(idex_insn), .iimm(iimm), .simm(simm), .bimm(bimm), .uimm(uimm), .jimm(jimm));
  alu    AL(.a(a_ex), .b(aluB_ex), .op(ce_alu_op), .res(alu_res), .eq(alu_eq),
             .slt_r(alu_slt_r), .sltu_r(alu_slt_u));

  fetch_pred FP(.clk(clk), .reset(reset), .fetch_insn(fetch_insn), .pc_if(pc_if),
              .idex_pc(idex_pc), .bp_upd_enable(bp_upd_enable),               .idex_pred_taken(idex_pred_taken),
              .branch_act_taken(branch_act_taken),
              .branch_upd_tgt(branch_upd_tgt), .wrong_pred(wrong_pred),
              .bp_pred_if(bp_pred_if), .bp_pred_tgt_if(bp_pred_tgt_if),
              .bp_branches(bp_branches), .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));

  always_comb begin
    if (st_ok) aluB_ex = simm;
    else if (ce_bsel) aluB_ex = iimm;
    else aluB_ex = b_ex;
  end

`ifdef FPGA
  assign idex_ea = alu_res;
`else
  assign idex_ea = ce_amo ? a_ex : alu_res;   // atomics have no offset (i[24:20] = rs2), rs1 forwarded
`endif
`ifdef FPGA
  assign amo_mmio_bad = 1'b0;
  assign ce_ex_ill = ce_ill;
`else
`ifdef DOOM_BIG
  localparam logic [31:0] UART_MMIO_PAGE = 32'h1FF0_0000;
`else
  localparam logic [31:0] UART_MMIO_PAGE = 32'h1000_0000;
`endif
  assign amo_mmio_bad = ce_amo &&
      (((a_ex & 32'hFFFF_F000) == 32'h0200_0000) ||
       ((a_ex & 32'hFFFF_F000) == UART_MMIO_PAGE));
  assign ce_ex_ill = ce_ill | amo_mmio_bad;
`endif
`ifdef FPGA
  assign amo_new = 32'h0;   // atomics are Linux-only; FPGA card keeps this dead
`else
  always_comb begin // AMO result ALU (MEM-side store of op(old,src); sim CPU only)
    case (ce_amo5)
      5'b00000: amo_new = ldx_raw + b_ex;   // AMOADD
      5'b00001: amo_new = b_ex;             // AMOSWAP
      5'b00100: amo_new = ldx_raw ^ b_ex;   // AMOXOR
      5'b01000: amo_new = ldx_raw | b_ex;   // AMOOR
      5'b01100: amo_new = ldx_raw & b_ex;   // AMOAND
      5'b10000: amo_new = ($signed(ldx_raw) < $signed(b_ex)) ? ldx_raw : b_ex; // AMOMIN
      5'b10100: amo_new = ($signed(ldx_raw) > $signed(b_ex)) ? ldx_raw : b_ex; // AMOMAX
      5'b11000: amo_new = (ldx_raw < b_ex) ? ldx_raw : b_ex;  // AMOMINU
      5'b11100: amo_new = (ldx_raw > b_ex) ? ldx_raw : b_ex;  // AMOMAXU
      5'b00011: amo_new = b_ex;            // SC.W: store value = rs2 (flag itself is ld_raw)
      default:  amo_new = ldx_raw;
    endcase
  end
`endif
  store  ST(.st_ok(st_ok), .ce_f3(ce_f3), .ea(idex_ea), .b_ex(b_ex),
            .ssz(idex_ssz), .sd_raw(idex_sd_raw), .sd_log(idex_sd_log), .sbe(idex_sbe_st));
`ifdef FPGA
  assign idex_sbe = idex_sbe_st;
`else
  assign idex_sbe = ce_amo ? 4'hF : idex_sbe_st;  // atomics: full-word store enable
`endif
  branch BR(.idex_valid(idex_valid), .idex_stop(idex_stop), .ce_br(ce_br), .ce_ill(ce_ill),
            .ce_jal(ce_jal), .ce_jalr(ce_jalr), .ce_f3(ce_f3), .idex_pc(idex_pc),
            .a_ex(a_ex), .iimm(iimm), .bimm(bimm), .jimm(jimm),
            .alu_eq(alu_eq), .alu_slt_r(alu_slt_r), .alu_slt_u(alu_slt_u),
            .pred_taken(idex_pred_taken), .pred_tgt(idex_pred_tgt),
            .branch_is(branch_is), .branch_act_taken(branch_act_taken),
            .branch_upd_tgt(branch_upd_tgt), .wrong_pred(wrong_pred),
            .flush_ex(flush_ex), .br_tgt_ex(br_tgt_ex));

  always_comb begin
    idex_wben = idex_valid && ((ce_rd != 5'd0) || ce_csr) &&
                ((ld_ok) || ce_lui || ce_auipc || ce_jal || (ce_jalr && !ce_ex_ill) ||
                 (ce_opi && !ce_ex_ill) || (ce_op && !ce_ex_ill) || ce_csr) && !ce_fence &&
                 !idex_stop && !idex_trap;
    idex_wbval = alu_res;
    if (ce_m && !ce_ill) idex_wbval = md_result;
    else if (ce_lui) idex_wbval = uimm;
    else if (ce_auipc) idex_wbval = idex_pc + uimm;
    else if (ce_jal || (ce_jalr && !ce_ill)) idex_wbval = idex_pc + 32'd4;
    else if (ce_csr) idex_wbval = 32'h0;

    idex_r1_cs = ifid_r1_fwd;
    if (ifid_valid && ceif_csr && (ceif_rs1 != 5'd0) && idex_valid && idex_wben && !idex_ld && !idex_st &&
        (idex_insn[11:7] == ceif_rs1))
      idex_r1_cs = idex_wbval;
  end

  always_comb begin
`ifdef FPGA
    stall = exmem_valid && exmem_ld && (exmem_rd != 5'd0) &&
            ((read_a && (ce_rs1 == exmem_rd)) || (read_b && (ce_rs2 == exmem_rd)));
`else
    stall = exmem_valid && (exmem_ld || exmem_is_amo) && (exmem_rd != 5'd0) &&
            ((read_a && (ce_rs1 == exmem_rd)) || (read_b && (ce_rs2 == exmem_rd)));
`endif
    mem_pend = idex_valid && (idex_ld || idex_st) && !mem_ready;
    // WFI retires as a nop; a pending IRQ traps before it (mepc = WFI pc).
`ifdef FPGA
    m_stall = (idex_m_go && (!idex_m_done || !fetch_ready)) || mem_pend;
`else
    m_stall = (idex_valid && ce_m && !ce_ill && !idex_m_done) || mem_pend;
`endif
  end

  always_comb begin
    bp_upd_enable = branch_is && !stall && !m_stall;
    idex_fetch_bad = 1'b0;
    if (idex_valid && !ce_ill) begin
      if (ce_jal && (((idex_pc + jimm) & 32'h3) != 0))
        idex_fetch_bad = 1'b1;
      else if (ce_jalr && ((((a_ex + iimm) & 32'hFFFFFFFE) & 32'h3) != 0))
        idex_fetch_bad = 1'b1;
      else if (ce_br && ((((idex_pc + bimm) & 32'hFFFFFFFE) & 32'h3) != 0)) begin
        case (ce_f3)
          3'b000: if (alu_eq) idex_fetch_bad = 1'b1;
          3'b001: if (!alu_eq) idex_fetch_bad = 1'b1;
          3'b100: if (alu_slt_r) idex_fetch_bad = 1'b1;
          3'b101: if (!alu_slt_r) idex_fetch_bad = 1'b1;
          3'b110: if (alu_slt_u) idex_fetch_bad = 1'b1;
          3'b111: if (!alu_slt_u) idex_fetch_bad = 1'b1;
          default: idex_fetch_bad = 1'b0;
        endcase
      end
    end
    flush = !stall && flush_ex && !trap_flush && !timer_flush && !mret_flush;
    conflict = !stall && !flush && idex_valid &&
               ((idex_st && (pc_if == idex_ea)) ||
                (exmem_valid && exmem_st && (pc_if == exmem_ea)));
  end

  csrs_pipe CSR1(.clk(clk), .reset(reset), .halt(halt),
            .idex_valid(idex_valid), .idex_insn(idex_insn), .idex_pc(idex_pc),
            .ce_sys(ce_sys), .ce_ill(ce_ex_ill), .ce_fetch_bad(idex_fetch_bad), .ce_mret(ce_mret), .ce_csr(ce_csr), .ce_f3(ce_f3), .ce_rs1(ce_rs1),
            .ld_ok(ld_ok), .st_ok(st_ok), .stall(stall), .m_stall(m_stall),
            .exmem_valid(exmem_valid), .exmem_csr_en(exmem_csr_en), .exmem_csr_wen(exmem_csr_wen),
            .exmem_insn(exmem_insn), .exmem_f3(exmem_f3), .exmem_r1(exmem_r1),
            .idex_ld(idex_ld), .idex_st(idex_st), .idex_trap(idex_trap), .idex_stop(idex_stop),
            .idex_csr_en(idex_csr_en), .idex_csr_wen(idex_csr_wen),
            .idex_ea(idex_ea), .idex_sd_raw(idex_sd_raw),
            .clint_commit(clint_commit), .clint_ld_data(clint_ld), .irq_pending(irq_pend),
            .trap_flush(trap_flush), .timer_flush(timer_flush), .mret_flush(mret_flush), .mret_pc(mret_pc),
            .idex_cs_old(idex_cs_old), .cs_old(cs_old), .cs_mtvec(cs_mtvec), .halt_out(halt_out));
`ifdef FPGA
  assign exmem_is_amo = 1'b0; assign exmem_is_lr = 1'b0; assign exmem_is_sc = 1'b0;
  assign amo_log_wr   = 1'b0;
  ldext LDX(.f3(exmem_f3), .raw(exmem_ld_raw), .ext(ldx_ex));
`else
  assign exmem_is_amo = ATOMIC && (exmem_insn[6:0] == 7'b010_1111);
  assign exmem_is_lr  = exmem_is_amo && exmem_insn[31:27] == 5'b00010 && exmem_insn[24:20] == 5'd0
                        && exmem_f3 == 3'b010;
  assign exmem_is_sc  = exmem_is_amo && exmem_insn[31:27] == 5'b00011 && exmem_f3 == 3'b010;
  assign amo_log_wr   = exmem_is_amo && !exmem_is_lr && (!exmem_is_sc || exmem_sc_ok);
  ldext LDX(.f3(exmem_is_amo ? 3'b010 : exmem_f3), .raw(exmem_ld_raw), .ext(ldx_ex));
`endif
`ifdef SCDBG
  always_comb if (idex_valid && ce_amo)
    $display("DBGTOP idex=%08x valid=%0d stall=%0d ce_sc=%0d ce_lr=%0d idex_ld=%0d idex_st=%0d",
             idex_insn, idex_valid, stall, ce_sc, ce_lr, idex_ld, idex_st);
`endif
  always_ff @(posedge clk) begin
    if (reset) begin
      pc_if <= 32'h0;
      halt <= 1'b0;
      ifid_valid <= 1'b0; idex_valid <= 1'b0; exmem_valid <= 1'b0; mwb_valid <= 1'b0;
      idex_m_done <= 1'b1;
`ifdef FPGA
      idex_m_go <= 1'b0;
`endif
`ifdef DOOM_BIG
      mst_cnt <= 32'd0;
      st_cnt <= 32'd0;
`endif
    end else if (!halt) begin
      halt <= halt || exmem_stop || halt_out;
`ifdef DOOM_BIG
      // P3 counters: M-unit + mem-pending stalls and load-use stalls
      mst_cnt <= mst_cnt + (m_stall ? 32'd1 : 32'd0);
      st_cnt <= st_cnt + (stall ? 32'd1 : 32'd0);
`endif
      mwb_valid <= exmem_valid;
      mwb_pc <= exmem_pc; mwb_insn <= exmem_insn; mwb_rd <= exmem_rd;
      mwb_wben <= exmem_wben && !exmem_stop;
      mwb_wv <= exmem_csr_en ? cs_old : (exmem_stop ? 32'h0
               : ((exmem_ld || exmem_is_amo) ? ldx_ex : exmem_wbval));
      mwb_stop <= exmem_stop;
      mwb_st <= (exmem_st || (exmem_is_amo && amo_log_wr)) && !exmem_stop;
      mwb_sa <= exmem_ea;
      mwb_sd <= exmem_is_amo ? exmem_amo_new : exmem_sd_log;
      mwb_sbe <= exmem_sbe;
      exmem_ld_raw <= ldx_raw;
`ifdef FPGA
      exmem_amo_new <= 32'h0; exmem_sc_ok <= 1'b0;
`else
      exmem_amo_new <= ATOMIC ? amo_new : 32'h0; exmem_sc_ok <= ATOMIC ? amo_sc_ok : 1'b0;
`endif

      if (mem_pend) begin
        exmem_valid <= 1'b0; idex_valid <= idex_valid; idex_m_done <= idex_m_done;
`ifdef FPGA
        idex_m_go <= idex_m_go;
`endif
        idex_pc <= idex_pc; idex_insn <= idex_insn; idex_r1 <= a_ex; idex_r2 <= b_ex;
        ifid_valid <= conflict ? 1'b0 : ifid_valid; ifid_pc <= ifid_pc; ifid_insn <= ifid_insn;
        ifid_pred_taken <= ifid_pred_taken; ifid_pred_tgt <= ifid_pred_tgt; pc_if <= pc_if;
      end else if (stall || m_stall) begin
        // Keep the forwarded operands: a value forwarded from MEM/WB this cycle is gone next cycle
        // (e.g. lw s6; lw a5; blt a5,s6 - s6 leaves WB during the load-use stall on a5).
        exmem_valid <= 1'b0; idex_valid <= idex_valid; idex_m_done <= idex_m_done;
`ifdef FPGA
        idex_m_go <= idex_m_go;
`endif
        idex_pc <= idex_pc; idex_insn <= idex_insn; idex_r1 <= a_ex; idex_r2 <= b_ex;
        ifid_valid <= ifid_valid; ifid_pc <= ifid_pc; ifid_insn <= ifid_insn;
        ifid_pred_taken <= ifid_pred_taken; ifid_pred_tgt <= ifid_pred_tgt; pc_if <= pc_if;
      end else if (trap_flush || timer_flush || mret_flush) begin
        exmem_valid <= mret_flush;
        exmem_pc <= idex_pc; exmem_insn <= idex_insn; exmem_rd <= 5'd0;
        exmem_wben <= 1'b0; exmem_ld <= 1'b0; exmem_st <= 1'b0; exmem_stop <= 1'b0;
        exmem_f3 <= 3'b0; exmem_ea <= idex_ea; exmem_sd_log <= 32'h0; exmem_sbe <= 4'h0;
        exmem_wbval <= 32'h0; exmem_result <= 32'h0;
        exmem_csr_en <= 1'b0; exmem_csr_wen <= 1'b0; exmem_r1 <= 32'h0;
        idex_valid <= 1'b0; ifid_valid <= 1'b0; idex_m_done <= 1'b1;
`ifdef FPGA
        idex_m_go <= 1'b0;
`endif
        pc_if <= mret_flush ? mret_pc : cs_mtvec;
      end else if (flush) begin
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc; exmem_insn <= idex_insn; exmem_rd <= ce_rd;
        exmem_wben <= idex_wben; exmem_ld <= idex_ld; exmem_st <= idex_st; exmem_stop <= idex_stop;
        exmem_f3 <= ce_f3; exmem_ea <= idex_ea;
        exmem_sd_log <= idex_sd_log; exmem_sbe <= idex_sbe;
        exmem_wbval <= idex_wbval; exmem_result <= idex_csr_en ? idex_cs_old : idex_wbval;
        exmem_csr_en <= idex_csr_en; exmem_csr_wen <= idex_csr_wen;
        exmem_r1 <= a_ex;   // CSR write data: the forwarded rs1 (lw t0,..; csrw mepc,t0 needs the load)
        idex_valid <= 1'b0; ifid_valid <= 1'b0; idex_m_done <= 1'b1;
`ifdef FPGA
        idex_m_go <= 1'b0;
`endif
        pc_if <= br_tgt_ex & 32'hFFFFFFFE;
      end else begin
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc; exmem_insn <= idex_insn; exmem_rd <= ce_rd;
        exmem_wben <= idex_wben; exmem_ld <= idex_ld; exmem_st <= idex_st; exmem_stop <= idex_stop;
        exmem_f3 <= ce_f3; exmem_ea <= idex_ea;
        exmem_sd_log <= idex_sd_log; exmem_sbe <= idex_sbe;
        exmem_wbval <= idex_wbval; exmem_result <= idex_csr_en ? idex_cs_old : idex_wbval;
        exmem_csr_en <= idex_csr_en; exmem_csr_wen <= idex_csr_wen;
        exmem_r1 <= a_ex;   // CSR write data: the forwarded rs1 (lw t0,..; csrw mepc,t0 needs the load)

        idex_valid <= ifid_valid;
        idex_pc <= ifid_pc; idex_insn <= ifid_insn; idex_r1 <= idex_r1_cs; idex_r2 <= ifid_r2_fwd;
        idex_pred_taken <= ifid_pred_taken; idex_pred_tgt <= ifid_pred_tgt;
        idex_m_done <= ifid_valid ? !(ceif_m && !ceif_ill) : 1'b1;
`ifdef FPGA
        idex_m_go   <= ifid_valid && ceif_m && !ceif_ill;
`endif
        if (conflict || !fetch_ready) begin
          ifid_valid <= 1'b0;
          ifid_pred_taken <= 1'b0; ifid_pred_tgt <= 32'h0;
          pc_if <= pc_if;
        end else begin
          ifid_valid <= 1'b1;
          ifid_pred_taken <= bp_pred_if;
          ifid_pred_tgt <= bp_pred_tgt_if;
          ifid_pc <= pc_if; ifid_insn <= fetch_insn;
          pc_if <= bp_pred_if ? bp_pred_tgt_if : (pc_if + 32'd4);
        end
      end
      if (m_done_now) idex_m_done <= 1'b1;
    end
  end

  assign ex_pc    = mwb_pc;
  assign ex_insn  = mwb_insn;
  assign ex_rd    = mwb_valid && !mwb_stop ? mwb_rd : 5'd0;
  assign ex_wben  = mwb_valid && mwb_wben;
  assign ex_wv    = mwb_wv;
  assign ex_st    = mwb_valid && mwb_st;
  assign ex_sa    = ex_st ? mwb_sa : 32'h0;
  assign ex_sd    = ex_st ? mwb_sd : 32'h0;
  assign ex_sbe   = ex_st ? mwb_sbe : 4'h0;
  assign rv_valid = mwb_valid && !reset;
endmodule
