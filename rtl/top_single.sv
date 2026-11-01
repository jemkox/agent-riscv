// Single-cycle clocked RV32I (M1). One instruction per clock boundary.
// Feeds (pc, insn, alu, wb select) are stable during each cycle; the clock block
// commits them at the 0->1 boundary. Loader port lwe/lwa/lwd for tb program load.
module top_single (
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
  logic [31:0] pc;
  logic [31:0] insn, ea, aluA, aluB, wb_wv, ldx, sda, tgt, ldraw, sd_raw;
  logic [3:0]  sbe, alu_op;
  logic [2:0]  f3;
   logic [4:0]  rs1c, rs2c, rdf;
   logic        is_m;
  logic [7:0]  rs2_b0, ld_b0;
  logic [15:0] ld_h0;
  logic        bself;
  logic [1:0]  ssz;
  logic        is_ld, is_st, is_br, is_jal, is_jalr, is_lui, is_auipc,
               is_opi, is_op, is_sys, is_fence, is_ill;
  logic [31:0] iimm, simm, bimm, uimm, jimm;
  logic        eqb, sltrb, sltub;
  logic [31:0] alures;
  logic        taken, wb_en, msw;
  logic [31:0] rs1, rs2;

  /* verilator lint_off PINCONNECTEMPTY */
  ctrl   C(.alu_op(alu_op), .f3(f3), .op7(), .rs1(rs1c), .rs2(rs2c), .rd(rdf),
           .a_sel(), .b_sel(bself),
           .is_ld(is_ld), .is_st(is_st), .is_br(is_br), .is_jal(is_jal),
           .is_jalr(is_jalr), .is_lui(is_lui), .is_auipc(is_auipc),
            .is_opi(is_opi), .is_op(is_op), .is_sys(is_sys), .is_fence(is_fence),
            .is_m(is_m), .m_op(), .is_mret(), .is_ill(is_ill), .i(insn));
  /* verilator lint_on PINCONNECTEMPTY */
  imm32  IM(.i(insn), .iimm(iimm), .simm(simm), .bimm(bimm), .uimm(uimm),
           .jimm(jimm));
  regs32 RF(.clk(clk), .reset(reset), .rsel1(rs1c), .rsel2(rs2c),
            .rs1(rs1), .rs2(rs2),
            .wena(wb_en && !halt && !reset), .wsel(rdf), .wdata(wb_wv));
  alu    AL(.a(aluA), .b(aluB), .op(alu_op), .res(alures),
            .eq(eqb), .slt_r(sltrb), .sltu_r(sltub));
  mem32  MM(.clk(clk), .ia(pc), .id(insn), .la(ea), .ld(ldraw),
            .sw(msw), .sa(ea), .sd(sd_raw), .ssz(ssz),
            .lwe(lwe), .lwa(lwa), .lwd(lwd));

  assign ea = alures;
  assign rs2_b0 = rs2[7:0];
  assign ld_b0 = ldraw[7:0];
  assign ld_h0 = ldraw[15:0];

  // A: ALU operands, branch condition, writeback enable (no mem-read deps)
  always_comb begin
    aluA = rs1;
    aluB = is_st ? simm : (bself ? iimm : rs2);
    taken = 1'b0;
    case (f3)
      3'b000: taken = eqb;
      3'b001: taken = !eqb;
      3'b100: taken = sltrb;
      3'b101: taken = !sltrb;
      3'b110: taken = sltub;
      3'b111: taken = !sltub;
      default: taken = 1'b0;
    endcase
    wb_en = (rdf != 5'd0) && (is_ld || is_lui || is_auipc || is_jal ||
             is_jalr || is_opi || is_op) && !is_fence && !is_ill && !is_sys && !is_m;
  end

  // B: target, store pack, side effects (no mem-read deps)
  always_comb begin
    if      (is_jal)       tgt = pc + jimm;
    else if (is_jalr)      tgt = (rs1 + iimm) & 32'hFFFFFFFE;
    else if (is_br)        tgt = taken ? (pc + bimm) : (pc + 4);
    else                   tgt = pc + 4;
    sbe = 4'b0000; sda = 32'h0; ssz = 2'b00; sd_raw = 32'h0;
    if (f3 == 3'b000) begin
      ssz = 2'b00; sd_raw = {24'h000000, rs2_b0};
      case (ea[1:0])
        2'b00: begin sbe = 4'b0001; sda = {24'h000000, rs2_b0}; end
        2'b01: begin sbe = 4'b0010; sda = {16'h0000, rs2_b0, 8'h00}; end
        2'b10: begin sbe = 4'b0100; sda = {8'h00, rs2_b0, 16'h0000}; end
        2'b11: begin sbe = 4'b1000; sda = {rs2_b0, 24'h000000}; end
      endcase
    end else if (f3 == 3'b001 || f3 == 3'b101) begin
      ssz = 2'b01; sd_raw = {16'h0000, rs2[15:0]};
      if (ea[1] == 1'b0) begin
        sbe = 4'b0011; sda = {16'h0000, rs2[15:0]};
      end else begin
        sbe = 4'b1100; sda = {rs2[15:0], 16'h0000};
      end
    end else begin
      ssz = 2'b10; sd_raw = rs2;
      sbe = 4'b1111; sda = rs2;
    end
    msw = is_st && !halt && !reset && !is_fence && !is_ill && !is_sys;
  end

  // C: load extension + writeback value (reads mem word)
  always_comb begin
    ldx = 32'h0;
    case (f3)
      3'b000: ldx = {{24{ld_b0[7]}}, ld_b0};
      3'b001: ldx = {{16{ld_h0[15]}}, ld_h0};
      3'b010: ldx = ldraw;
      3'b100: ldx = {24'h000000, ld_b0};
      3'b101: ldx = {16'h0000, ld_h0};
      default: ldx = ldraw;
    endcase
    wb_wv = alures;
    if      (is_ld)             wb_wv = ldx;
    else if (is_lui)            wb_wv = uimm;
    else if (is_auipc)          wb_wv = pc + uimm;
    else if (is_jal || is_jalr) wb_wv = pc + 4;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      pc <= 32'h0;
      halt <= 1'b0;
    end else if (!halt) begin
      pc <= tgt;
      if (is_ill || is_sys)
        halt <= 1;
    end
  end

  assign ex_pc    = pc;
  assign ex_insn  = insn;
  assign ex_wben  = wb_en && !halt && !reset;
  assign ex_rd    = (is_ill || is_sys) ? 5'd0 : rdf;
  assign ex_wv    = wb_wv;
  assign ex_st    = msw;
  assign ex_sa    = msw ? ea : 32'h0;
  assign ex_sd    = msw ? sda : 32'h0;
  assign ex_sbe   = msw ? sbe : 4'h0;
  assign rv_valid = !halt && !reset;
  assign bp_branches = 32'h0;
  assign bp_taken_preds = 32'h0;
  assign bp_mispreds = 32'h0;
endmodule
