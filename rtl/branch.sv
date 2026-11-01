// branch.sv — RV32 branch target, taken direction, and predictor check.
`default_nettype none
module branch (
  input  logic        idex_valid,
  input  logic        idex_stop,
  input  logic        ce_br,
  input  logic        ce_ill,
  input  logic        ce_jal,
  input  logic        ce_jalr,
  input  logic [2:0]  ce_f3,
  input  logic [31:0] idex_pc,
  input  logic [31:0] a_ex,
  input  logic [31:0] iimm,
  input  logic [31:0] bimm,
  input  logic [31:0] jimm,
  input  logic        alu_eq,
  input  logic        alu_slt_r,
  input  logic        alu_slt_u,
  input  logic        pred_taken,
  input  logic [31:0] pred_tgt,
  output logic        branch_is,
  output logic        branch_act_taken,
  output logic [31:0] branch_upd_tgt,
  output logic        wrong_pred,
  output logic        flush_ex,
  output logic [31:0] br_tgt_ex
);
  logic [31:0] tgt;
  logic        act;
  always_comb begin
    branch_is = idex_valid && !idex_stop && ((ce_br && !ce_ill) || ce_jal || (ce_jalr && !ce_ill));
    act = 1'b0;
    tgt = idex_pc + 32'd4;
    if (branch_is) begin
      if (ce_jal) begin
        act = 1'b1;
        tgt = idex_pc + jimm;
      end else if (ce_jalr && !ce_ill) begin
        act = 1'b1;
        tgt = (a_ex + iimm) & 32'hFFFFFFFE;
      end else begin
        if (ce_f3 == 3'b000) act = alu_eq;
        else if (ce_f3 == 3'b001) act = !alu_eq;
        else if (ce_f3 == 3'b100) act = alu_slt_r;
        else if (ce_f3 == 3'b101) act = !alu_slt_r;
        else if (ce_f3 == 3'b110) act = alu_slt_u;
        else if (ce_f3 == 3'b111) act = !alu_slt_u;
        act = act;
        tgt = (idex_pc + bimm) & 32'hFFFFFFFE;
      end
    end
    if (act) wrong_pred = branch_is && !(pred_taken && (pred_tgt == tgt));
    else wrong_pred = branch_is && pred_taken;
    flush_ex = wrong_pred;
    branch_act_taken = act;
    branch_upd_tgt = tgt;
    br_tgt_ex = act ? tgt : (idex_pc + 32'd4);
  end
endmodule
`default_nettype wire
