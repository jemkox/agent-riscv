// M-Linux wrapper for the Linux runner: top-level ports so the Verilated C++
// main can drive the clock/loader/UART and watch retire signals.
`default_nettype none
module run_linux (
  input  logic        clk,
  input  logic        reset,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd,
  input  logic [31:0] linux_dtb_addr,
  input  logic        uart_rx_ready,
  input  logic [7:0]  uart_rx_in,
  output logic        uart_tx_valid,
  output logic [7:0]  uart_tx_out,
  output logic        uart_rx_pending,
  output logic        uart_tx_ready,
  output logic        halt,
  output logic [31:0] ex_pc,
  output logic [31:0] ex_insn,
  output logic        ex_wben,
  output logic [4:0]  ex_rd,
  output logic [31:0] ex_wv,
  output logic        ex_st,
  output logic [31:0] ex_sa,
  output logic [31:0] ex_sd,
  output logic [31:0] ex_ea,
  output logic [3:0]  ex_sbe,
  output logic        rv_valid,
  output logic [31:0] bp_branches,
  output logic [31:0] bp_taken_preds,
  output logic [31:0] bp_mispreds
);
  top_pipe T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
             .linux_dtb_addr(linux_dtb_addr),
             .uart_rx_ready(uart_rx_ready), .uart_rx_in(uart_rx_in),
             .uart_tx_valid(uart_tx_valid), .uart_tx_out(uart_tx_out),
             .uart_rx_pending(uart_rx_pending), .uart_tx_ready(uart_tx_ready),
             .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
             .ex_wben(ex_wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
              .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_ea(ex_ea), .ex_sbe(ex_sbe),
             .rv_valid(rv_valid), .bp_branches(bp_branches),
             .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));
endmodule
`default_nettype wire
