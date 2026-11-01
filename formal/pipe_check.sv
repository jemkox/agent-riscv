// Tiny formal pipeline model used to prove structural pipeline invariants.
// The simulation design has the same invariants checked in top_pipe.sv, but
// this model is intentionally compact so SBY can prove the inductive part.
module pipe_check (
  input  logic        clk,
  input  logic        reset,
  input  logic        br_taken,
  input  logic        idex_ld,
  input  logic        idex_st,
  input  logic        exmem_st,
  input  logic [31:0] idex_ea,
  input  logic [31:0] exmem_ea,
  input  logic        idex_wben,
  input  logic [4:0]  idex_rd,
  input  logic [4:0]  ce_rs1,
  input  logic [4:0]  ce_rs2
);
  logic [31:0] pc_if = 0;
  logic [31:0] ifid_pc = 0, idex_pc = 0, exmem_pc = 0, mwb_pc = 0;
  logic ifid_valid = 0, idex_valid = 0, exmem_valid = 0, mwb_valid = 0;
  logic exmem_ld = 0;
  logic [4:0] exmem_rd = 0, mwb_rd = 0;
  logic [31:0] rf0 = 0;
  logic read_a, read_b, stall, flush, conflict;
  logic rf1, rf2;
  logic [4:0] rf_sel1 = 0, rf_sel2 = 0;

  always_comb begin
    read_a = (ce_rs1 != 5'd0);
    read_b = (ce_rs2 != 5'd0);
    stall = exmem_valid && exmem_ld && idex_valid && ifid_valid &&
            ((read_a && (ce_rs1 == exmem_rd)) || (read_b && (ce_rs2 == exmem_rd)));
    flush = br_taken && idex_valid && !stall;
    conflict = idex_valid && ((idex_st && (pc_if == idex_ea)) ||
                              (exmem_valid && exmem_st && (pc_if == exmem_ea)));

    assert(pc_if[1:0] == 2'b00);
    if (ifid_valid) assert(ifid_pc[1:0] == 2'b00);
    if (idex_valid) assert(idex_pc[1:0] == 2'b00);
    if (exmem_valid) assert(exmem_pc[1:0] == 2'b00);
    if (mwb_valid) assert(mwb_pc[1:0] == 2'b00);

    assert(!(stall && flush));

    if (stall) begin
      assert(ifid_valid);
      assert(idex_valid);
      assert(exmem_valid && exmem_ld);
      assert(read_a || read_b);
    end

    if (mwb_valid && idex_wben && (mwb_rd == 5'd0)) begin
      // Allowed only because the architectural x0 write is ignored.
    end

    if (rf_sel1 == 5'd0) assert(rf0 == 32'h0);
    if (rf_sel2 == 5'd0) assert(rf0 == 32'h0);
    assert(rf0 == 32'h0);
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      pc_if <= 32'h0;
      ifid_pc <= 32'h0;
      idex_pc <= 32'h0;
      exmem_pc <= 32'h0;
      mwb_pc <= 32'h0;
      ifid_valid <= 0;
      idex_valid <= 0;
      exmem_valid <= 0;
      mwb_valid <= 0;
      exmem_ld <= 0;
      exmem_rd <= 0;
      mwb_rd <= 0;
      rf0 <= 32'h0;
    end else begin
      if (stall) begin
        pc_if <= ifid_pc;
        ifid_valid <= ifid_valid;
        ifid_pc <= ifid_pc;
        idex_valid <= idex_valid;
        idex_pc <= idex_pc;
        exmem_valid <= exmem_valid;
        exmem_pc <= exmem_pc;
        exmem_rd <= exmem_rd;
        mwb_valid <= exmem_valid;
        mwb_pc <= exmem_pc;
        mwb_rd <= exmem_rd;
      end else if (flush || conflict) begin
        pc_if <= (flush) ? (idex_pc & 32'hfffffffe) : pc_if;
        ifid_valid <= idex_valid;
        ifid_pc <= idex_pc;
        idex_valid <= 0;
        idex_pc <= idex_pc;
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc;
        exmem_rd <= idex_rd;
        mwb_valid <= exmem_valid;
        mwb_pc <= exmem_pc;
        mwb_rd <= exmem_rd;
      end else begin
        pc_if <= pc_if + 32'h4;
        ifid_valid <= idex_valid;
        ifid_pc <= idex_pc;
        idex_valid <= ifid_valid;
        idex_pc <= ifid_pc;
        exmem_valid <= idex_valid;
        exmem_pc <= idex_pc;
        exmem_rd <= idex_rd;
        mwb_valid <= exmem_valid;
        mwb_pc <= exmem_pc;
        mwb_rd <= exmem_rd;
      end

      if (mwb_valid && idex_wben && (mwb_rd != 5'd0)) begin
        // A real write to a nonzero register does not affect rf0.
      end
      if (mwb_valid && idex_wben && (mwb_rd == 5'd0)) begin
        rf0 <= rf0; // ignored x0 write
      end
    end
  end
endmodule