// ifdec.sv — instruction-fetch branch/jump classification for predictor query.
`default_nettype none
module ifdec (
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] fetch_insn,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic        if_br,
  output logic        if_jal,
  output logic        if_jalr,
  output logic        if_bp
);
  always_comb begin
    if_br = (fetch_insn[6:0] == 7'b1100011) &&
            (fetch_insn[14:12] != 3'b010) && (fetch_insn[14:12] != 3'b011);
    if_jal = (fetch_insn[6:0] == 7'b1101111);
    if_jalr = (fetch_insn[6:0] == 7'b1100111) && (fetch_insn[14:12] == 3'b000);
    if_bp = if_br || if_jal || if_jalr;
  end
endmodule
`default_nettype wire
