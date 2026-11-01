// bpif.sv — instruction-fetch branch/jump predictor target selection.
`default_nettype none
module bpif (
  input  logic [31:0] fetch_insn,
  input  logic [31:0] pc_if,
  input  logic        if_br,
  input  logic        if_jal,
  input  logic        if_jalr,
  input  logic        bp_q_valid,
  input  logic        bp_q_taken,
  input  logic [31:0] bp_q_target,
  output logic        bp_pred_if,
  output logic [31:0] bp_pred_tgt_if
);
  logic [31:0] bimm, jimm;
  /* verilator lint_off PINCONNECTEMPTY */
  imm32  IM(.i(fetch_insn), .iimm(), .simm(), .bimm(bimm), .uimm(), .jimm(jimm));
  /* verilator lint_on PINCONNECTEMPTY */
  always_comb begin
    bp_pred_if = if_jal || (bp_q_valid && bp_q_taken && (if_br || if_jalr));
    if (if_jal) bp_pred_tgt_if = (pc_if + jimm) & 32'hFFFFFFFE;
    else if (if_br) bp_pred_tgt_if = (pc_if + bimm) & 32'hFFFFFFFE;
    else bp_pred_tgt_if = bp_q_target & 32'hFFFFFFFE;
  end
endmodule
`default_nettype wire
