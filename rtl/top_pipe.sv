// 5-stage in-order RV32I pipeline: IF/ID/EX/MEM/WB.
// Retire output comes from MEM/WB; rv_valid gates retired instructions only.
module top_pipe (
  input  logic        clk,
  input  logic        reset,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd,
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
  logic [31:0] ifid_pc = 0, ifid_insn = 0, idex_pc = 0, idex_insn = 0;
  logic [31:0] idex_r1 = 0, idex_r2 = 0;
  logic [31:0] exmem_pc = 0, exmem_insn = 0, exmem_result = 0, exmem_wbval = 0;
  logic [31:0] exmem_ea = 0, exmem_sd_raw = 0, exmem_sd_log = 0;
  logic [31:0] mwb_pc = 0, mwb_insn = 0, mwb_sa = 0, mwb_sd = 0, mwb_wv = 0;
  logic [4:0]  exmem_rd = 0, mwb_rd = 0;
  logic [31:0] a_ex, b_ex, aluB_ex, br_tgt_ex;
  logic [31:0] iimm, simm, bimm, uimm, jimm;
  logic [31:0] fetch_insn, rf_r1, rf_r2;
  logic [31:0] idex_ea, idex_sd_raw, idex_sd_log, idex_wbval;
  logic [31:0] ldx_raw, ldx_ex;
  logic [3:0]  ce_alu_op, idex_sbe;
  logic [3:0]  exmem_sbe = 0, mwb_sbe = 0;
  logic [1:0]  idex_ssz;
  logic [1:0]  exmem_ssz = 0;
  logic [2:0]  ce_f3;
  logic [2:0]  exmem_f3 = 0;
  logic [4:0]  ce_rs1, ce_rs2, ce_rd;
  logic [31:0] alu_res;
  logic        alu_eq, alu_slt_r, alu_slt_u;

  // pipeline valid/stage control bits
  logic ifid_valid = 0, idex_valid = 0, exmem_valid = 0, mwb_valid = 0;
  logic idex_m_done = 1'b1;
  logic m_stall, m_done_now;
  logic exmem_ld = 0, exmem_st = 0, exmem_stop = 0, exmem_wben = 0;
  logic mwb_st = 0, mwb_stop = 0, mwb_wben = 0;
  logic stall, flush, conflict, flush_ex;
  logic ld_ok, st_ok, idex_stop, idex_wben, idex_ld, idex_st;
  logic read_a, read_b;
  logic ce_bsel, ce_ld, ce_st, ce_br, ce_jal, ce_jalr;
  logic ce_lui, ce_auipc, ce_opi, ce_op, ce_sys, ce_fence;
  logic ce_ill, ce_m;
  logic ceif_ill, ceif_m;
  logic [2:0] ce_m_op;
  logic [31:0] md_result;
  logic [4:0] ceif_rs1, ceif_rs2;
  logic ceif_ld, ceif_st, ceif_br, ceif_jalr, ceif_opi, ceif_op;
  logic [31:0] ifid_r1_fwd, ifid_r2_fwd;
  logic if_br, if_jal, if_jalr, if_bp;
  logic bp_q_valid, bp_q_taken, ifid_pred_taken = 0, idex_pred_taken = 0;
  logic [31:0] bp_q_target, ifid_pred_tgt = 0, idex_pred_tgt = 0;
  logic bp_pred_if;
  logic [31:0] bp_pred_tgt_if;
  logic branch_act_taken, branch_is, wrong_pred, bp_upd_enable;
  logic [31:0] branch_upd_tgt;
  // stats counters live in btb.sv.

  regs32 RF(.clk(clk), .reset(reset), .rsel1(ifid_insn[19:15]), .rsel2(ifid_insn[24:20]),
            .rs1(rf_r1), .rs2(rf_r2),
            .wena(mwb_valid && mwb_wben && (mwb_rd != 5'd0) && !halt && !reset), .wsel(mwb_rd), .wdata(mwb_wv));
  mem32  MM(.clk(clk), .ia(pc_if), .id(fetch_insn), .la(exmem_ea), .ld(ldx_raw),
            .sw(exmem_valid && exmem_st && !halt && !reset), .sa(exmem_ea),
            .sd(exmem_sd_raw), .ssz(exmem_ssz), .lwe(lwe), .lwa(lwa), .lwd(lwd));
  /* verilator lint_off PINCONNECTEMPTY */
  ctrl   CE(.alu_op(ce_alu_op), .f3(ce_f3), .op7(), .rs1(ce_rs1), .rs2(ce_rs2), .rd(ce_rd),
            .a_sel(), .b_sel(ce_bsel), .is_ld(ce_ld), .is_st(ce_st), .is_br(ce_br),
            .is_jal(ce_jal), .is_jalr(ce_jalr), .is_lui(ce_lui), .is_auipc(ce_auipc),
            .is_opi(ce_opi), .is_op(ce_op),              .is_sys(ce_sys), .is_fence(ce_fence),
             .is_m(ce_m), .m_op(ce_m_op), .is_mret(), .is_ill(ce_ill), .i(idex_insn));
  mdiu MD(.clk(clk), .reset(reset), .idex_valid(idex_valid), .is_m(ce_m), .is_ill(ce_ill),
          .idex_done(idex_m_done), .op(ce_m_op), .a(a_ex), .b(b_ex), .ex_stall(stall),
          /* verilator lint_off PINCONNECTEMPTY */
          .md_active(), .md_done_now(m_done_now), .result(md_result));
          /* verilator lint_on PINCONNECTEMPTY */
  /* verilator lint_on PINCONNECTEMPTY */
  /* verilator lint_off PINCONNECTEMPTY */
  ctrl   CEID(.alu_op(), .f3(), .op7(), .rs1(ceif_rs1), .rs2(ceif_rs2), .rd(),
              .a_sel(), .b_sel(), .is_ld(ceif_ld), .is_st(ceif_st),
              .is_br(ceif_br), .is_jal(), .is_jalr(ceif_jalr),
              .is_lui(), .is_auipc(), .is_opi(ceif_opi), .is_op(ceif_op),
              .is_sys(), .is_fence(), .is_m(ceif_m), .m_op(),
              .is_mret(), .is_ill(ceif_ill), .i(ifid_insn));
  /* verilator lint_on PINCONNECTEMPTY */
  ldst  LDST(.is_ld(ce_ld), .is_st(ce_st), .is_ill(ce_ill), .ld_ok(ld_ok), .st_ok(st_ok));
  fwd   FWDD(.idex_valid(idex_valid), .ce_br(ce_br), .ce_jalr(ce_jalr), .ce_opi(ce_opi),
             .ce_op(ce_op), .ld_ok(ld_ok), .st_ok(st_ok), .ce_rs1(ce_rs1), .ce_rs2(ce_rs2),
             .idex_r1(idex_r1), .idex_r2(idex_r2),
             .exmem_valid(exmem_valid), .exmem_rd(exmem_rd), .exmem_wben(exmem_wben),
             .exmem_ld(exmem_ld), .exmem_st(exmem_st), .exmem_stop(exmem_stop),
             .exmem_result(exmem_result), .mwb_valid(mwb_valid), .mwb_rd(mwb_rd),
             .mwb_wben(mwb_wben), .mwb_wv(mwb_wv),
             .ifid_valid(ifid_valid), .ifid_r1(rf_r1), .ifid_r2(rf_r2),
             .ceif_br(ceif_br), .ceif_jalr(ceif_jalr), .ceif_ld(ceif_ld), .ceif_st(ceif_st),
             .ceif_opi(ceif_opi), .ceif_op(ceif_op), .ceif_rs1(ceif_rs1), .ceif_rs2(ceif_rs2),
             .a_ex(a_ex), .b_ex(b_ex), .read_a(read_a), .read_b(read_b),
             .ifid_r1_fwd(ifid_r1_fwd), .ifid_r2_fwd(ifid_r2_fwd));
  imm32  IM(.i(idex_insn), .iimm(iimm), .simm(simm), .bimm(bimm), .uimm(uimm), .jimm(jimm));
  alu    AL(.a(a_ex), .b(aluB_ex), .op(ce_alu_op), .res(alu_res), .eq(alu_eq),
             .slt_r(alu_slt_r), .sltu_r(alu_slt_u));

  ifdec IFDEC(.fetch_insn(fetch_insn), .if_br(if_br), .if_jal(if_jal), .if_jalr(if_jalr), .if_bp(if_bp));
  btb BTB(.clk(clk), .reset(reset), .q_enable(if_bp), .q_pc(pc_if), .q_br(if_br),
           .q_jal(if_jal), .q_jalr(if_jalr),            .q_valid(bp_q_valid), .q_taken(bp_q_taken), .q_target(bp_q_target),
           .out_branches(bp_branches), .out_taken_preds(bp_taken_preds), .out_mispreds(bp_mispreds),
           .upd_enable(bp_upd_enable), .upd_pc(idex_pc), .upd_taken(branch_act_taken), .upd_target(branch_upd_tgt),
           .upd_pred_taken(idex_pred_taken), .upd_mispred(wrong_pred));
  bpif BPIF(.fetch_insn(fetch_insn), .pc_if(pc_if), .if_br(if_br), .if_jal(if_jal), .if_jalr(if_jalr),
             .bp_q_valid(bp_q_valid), .bp_q_taken(bp_q_taken), .bp_q_target(bp_q_target),
             .bp_pred_if(bp_pred_if), .bp_pred_tgt_if(bp_pred_tgt_if));

  always_comb begin
    if (st_ok) aluB_ex = simm;
    else if (ce_bsel) aluB_ex = iimm;
    else aluB_ex = b_ex;
  end

  always_comb begin
    idex_ld = idex_valid && ld_ok;
    idex_st = idex_valid && st_ok;
    idex_stop = idex_valid && (ce_sys || ce_ill);
    idex_ea = alu_res;
  end

  store  ST(.st_ok(st_ok), .ce_f3(ce_f3), .ea(idex_ea), .b_ex(b_ex),
            .ssz(idex_ssz), .sd_raw(idex_sd_raw), .sd_log(idex_sd_log), .sbe(idex_sbe));
  branch BR(.idex_valid(idex_valid), .idex_stop(idex_stop), .ce_br(ce_br), .ce_ill(ce_ill),
            .ce_jal(ce_jal), .ce_jalr(ce_jalr), .ce_f3(ce_f3), .idex_pc(idex_pc),
            .a_ex(a_ex), .iimm(iimm), .bimm(bimm), .jimm(jimm),
            .alu_eq(alu_eq), .alu_slt_r(alu_slt_r), .alu_slt_u(alu_slt_u),
            .pred_taken(idex_pred_taken), .pred_tgt(idex_pred_tgt),
            .branch_is(branch_is), .branch_act_taken(branch_act_taken),
            .branch_upd_tgt(branch_upd_tgt), .wrong_pred(wrong_pred),
            .flush_ex(flush_ex), .br_tgt_ex(br_tgt_ex));

  always_comb begin
    idex_wben = idex_valid && (ce_rd != 5'd0) &&
                ((ld_ok) || ce_lui || ce_auipc || ce_jal || (ce_jalr && !ce_ill) ||
                 (ce_opi && !ce_ill) || (ce_op && !ce_ill)) && !ce_fence && !idex_stop;
    idex_wbval = alu_res;
    if (ce_m && !ce_ill) idex_wbval = md_result;
    else if (ce_lui) idex_wbval = uimm;
    else if (ce_auipc) idex_wbval = idex_pc + uimm;
    else if (ce_jal || (ce_jalr && !ce_ill)) idex_wbval = idex_pc + 32'd4;

    stall = exmem_valid && exmem_ld && (exmem_rd != 5'd0) &&
            ((read_a && (ce_rs1 == exmem_rd)) || (read_b && (ce_rs2 == exmem_rd)));
    m_stall = idex_valid && ce_m && !ce_ill && !idex_m_done;
    bp_upd_enable = branch_is && !stall && !m_stall;
    flush = !stall && flush_ex;
    conflict = !stall && !flush && idex_valid &&
               ((idex_st && (pc_if == idex_ea)) ||
                (exmem_valid && exmem_st && (pc_if == exmem_ea)));
  end

  ldext LDX(.f3(exmem_f3), .raw(ldx_raw), .ext(ldx_ex));

  always_ff @(posedge clk) begin
    if (reset) begin
      pc_if <= 32'h0;
      halt <= 1'b0;
      ifid_valid <= 1'b0; idex_valid <= 1'b0; exmem_valid <= 1'b0; mwb_valid <= 1'b0;
      idex_m_done <= 1'b1;
    end else if (!halt) begin
      halt <= halt || exmem_stop;
      mwb_valid <= exmem_valid;
      mwb_pc <= exmem_pc; mwb_insn <= exmem_insn; mwb_rd <= exmem_rd;
      mwb_wben <= exmem_wben && !exmem_stop;
      mwb_wv <= exmem_stop ? 32'h0 : (exmem_ld ? ldx_ex : exmem_wbval);
      mwb_stop <= exmem_stop;
      mwb_st <= exmem_st && !exmem_stop;
      mwb_sa <= exmem_ea; mwb_sd <= exmem_sd_log; mwb_sbe <= exmem_sbe;

      if (stall || m_stall) begin
        exmem_valid <= 1'b0;
        idex_valid <= idex_valid;
        idex_pc <= idex_pc; idex_insn <= idex_insn; idex_r1 <= idex_r1; idex_r2 <= idex_r2;
        idex_m_done <= idex_m_done;
        ifid_valid <= 1'b0;
        pc_if <= ifid_valid ? ifid_pc : pc_if;
      end else if (flush) begin
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc; exmem_insn <= idex_insn; exmem_rd <= ce_rd;
        exmem_wben <= idex_wben; exmem_ld <= idex_ld; exmem_st <= idex_st; exmem_stop <= idex_stop;
        exmem_f3 <= ce_f3; exmem_ea <= idex_ea; exmem_ssz <= idex_ssz;
        exmem_sd_raw <= idex_sd_raw; exmem_sd_log <= idex_sd_log; exmem_sbe <= idex_sbe;
        exmem_wbval <= idex_wbval; exmem_result <= idex_wbval;
        idex_valid <= 1'b0; ifid_valid <= 1'b0; idex_m_done <= 1'b1;
        pc_if <= br_tgt_ex & 32'hFFFFFFFE;
      end else begin
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc; exmem_insn <= idex_insn; exmem_rd <= ce_rd;
        exmem_wben <= idex_wben; exmem_ld <= idex_ld; exmem_st <= idex_st; exmem_stop <= idex_stop;
        exmem_f3 <= ce_f3; exmem_ea <= idex_ea; exmem_ssz <= idex_ssz;
        exmem_sd_raw <= idex_sd_raw; exmem_sd_log <= idex_sd_log; exmem_sbe <= idex_sbe;
        exmem_wbval <= idex_wbval; exmem_result <= idex_wbval;

        idex_valid <= ifid_valid;
        idex_pc <= ifid_pc; idex_insn <= ifid_insn; idex_r1 <= ifid_r1_fwd; idex_r2 <= ifid_r2_fwd;
        idex_pred_taken <= ifid_pred_taken; idex_pred_tgt <= ifid_pred_tgt;
        idex_m_done <= ifid_valid ? !(ceif_m && !ceif_ill) : 1'b1;
        if (conflict) begin
          ifid_valid <= 1'b0;
          ifid_pred_taken <= 1'b0; ifid_pred_tgt <= 32'h0;
          idex_m_done <= 1'b1;
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
