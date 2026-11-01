// Fetch prediction helper: ifdec + BTB + prediction selection.
module fetch_pred (
  input  logic        clk,
  input  logic        reset,
  input  logic [31:0] fetch_insn,
  input  logic [31:0] pc_if,
  input  logic [31:0] idex_pc,
  input  logic        bp_upd_enable,
  input  logic        idex_pred_taken,
  input  logic        branch_act_taken,
  input  logic [31:0] branch_upd_tgt,
  input  logic        wrong_pred,
  output logic        bp_pred_if,
  output logic [31:0] bp_pred_tgt_if,
  output logic [31:0] bp_branches,
  output logic [31:0] bp_taken_preds,
  output logic [31:0] bp_mispreds
);
  logic if_br, if_jal, if_jalr, if_bp;
  logic bp_q_valid, bp_q_taken;
  logic [31:0] bp_q_target;

  ifdec IFDEC(.fetch_insn(fetch_insn), .if_br(if_br), .if_jal(if_jal), .if_jalr(if_jalr), .if_bp(if_bp));
  btb BTB(.clk(clk), .reset(reset), .q_enable(if_bp), .q_pc(pc_if), .q_br(if_br),
          .q_jal(if_jal), .q_jalr(if_jalr),
          .q_valid(bp_q_valid), .q_taken(bp_q_taken), .q_target(bp_q_target),
          .out_branches(bp_branches), .out_taken_preds(bp_taken_preds), .out_mispreds(bp_mispreds),
          .upd_enable(bp_upd_enable), .upd_pc(idex_pc), .upd_taken(branch_act_taken), .upd_target(branch_upd_tgt),
          .upd_pred_taken(idex_pred_taken), .upd_mispred(wrong_pred));
  bpif BPIF(.fetch_insn(fetch_insn), .pc_if(pc_if), .if_br(if_br), .if_jal(if_jal), .if_jalr(if_jalr),
            .bp_q_valid(bp_q_valid), .bp_q_taken(bp_q_taken), .bp_q_target(bp_q_target),
            .bp_pred_if(bp_pred_if), .bp_pred_tgt_if(bp_pred_tgt_if));
endmodule
