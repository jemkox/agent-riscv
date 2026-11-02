// M10b wrapper for the Doom runner: top-level ports so the Verilated C++ main
// can drive the clock/loader/dbg-readback and watch EX/MEM + retire signals.
`default_nettype none
module run_doom (
  input  logic        clk,
  input  logic        reset,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd,
  input  logic        dbg_re,
  input  logic [31:0] dbg_ra,
  output logic        halt,
  output logic [31:0] dbg_rd,
  input  logic [31:0] key_in,
  output logic        key_hit,
  output logic [31:0] stat_icm,
  output logic [31:0] stat_dcm,
  output logic [31:0] mst_cnt,
  output logic [31:0] st_cnt,
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
  top_pipe T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
             .dbg_re(dbg_re), .dbg_ra(dbg_ra), .dbg_rd(dbg_rd),
             .key_in(key_in), .key_hit(key_hit),
             .stat_icm(stat_icm), .stat_dcm(stat_dcm),
             .mst_cnt(mst_cnt), .st_cnt(st_cnt),
             .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
             .ex_wben(ex_wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
             .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_sbe(ex_sbe),
             .rv_valid(rv_valid), .bp_branches(bp_branches),
             .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));
endmodule
`default_nettype wire
