// M10b wrapper for the Doom runner. The Verilated C++ main loads the ELF and WAD
// through the loader port and runs top_pipe; this file only exposes the CPU ports.
`default_nettype none
module run_doom ();
  /* verilator lint_off UNUSED */
  logic clk = 0, reset = 1;
  logic lwe = 0, halt, wben;
  logic [31:0] lwa = 0, lwd = 0;
  logic [31:0] ex_pc, ex_insn, ex_wv;
  logic [31:0] ex_sa, ex_sd;
  logic [4:0]  ex_rd;
  logic [3:0]  ex_sbe;
  logic        ex_st;
  logic        rv_valid;
  logic [31:0] bp_branches, bp_taken_preds, bp_mispreds;

  top_pipe T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
             .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
             .ex_wben(wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
             .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_sbe(ex_sbe),
             .rv_valid(rv_valid), .bp_branches(bp_branches),
             .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));
  /* verilator lint_on UNUSED */
endmodule
`default_nettype wire
