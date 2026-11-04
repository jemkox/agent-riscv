// FPGA-friendly full-CPU top: full top_pipe + UART TX.
// Program lives in cache32_fpga's RAM INIT (fpga_prog_init.sv); no runtime ROM loader.
`default_nettype none
module fpga_pipe_top (
  input  logic        clk,
  input  logic        reset,
  output logic [7:0]  uart_tx,
  output logic        uart_tx_valid,
  output logic        halt
);
  localparam [31:0] UART_ADDR = 32'h1000_0000;

  logic        lwe;
  logic [31:0] lwa;
  logic [31:0] lwd;
  logic        pipe_reset;

  logic        ex_st;
  logic [31:0] ex_sa;
  logic [31:0] ex_sd;
  logic [3:0]  ex_sbe;
  logic        dummy_wben, dummy_rv;
  logic [31:0] dummy_pc, dummy_insn, dummy_wv;
  logic [4:0]  dummy_rd;
  /* verilator lint_off UNUSED */
  logic [31:0] dummy_ea;
  /* verilator lint_on UNUSED */
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] dummy_branches, dummy_taken, dummy_misps;
  /* verilator lint_on UNUSEDSIGNAL */

  assign pipe_reset = reset;
  assign lwe = 1'b0;
  assign lwa = 32'h0;
  assign lwd = 32'h0;

  top_pipe CPU(
    .clk(clk),
    .reset(pipe_reset),
    .lwe(lwe),
    .lwa(lwa),
    .lwd(lwd),
    .halt(halt),
    .ex_pc(dummy_pc),
    .ex_insn(dummy_insn),
    .ex_wben(dummy_wben),
    .ex_rd(dummy_rd),
    .ex_wv(dummy_wv),
    .ex_st(ex_st),
    .ex_sa(ex_sa),
    .ex_sd(ex_sd),
    .ex_ea(dummy_ea),
    .ex_sbe(ex_sbe),
    .rv_valid(dummy_rv),
    .bp_branches(dummy_branches),
    .bp_taken_preds(dummy_taken),
    .bp_mispreds(dummy_misps)
  );

  always_comb begin
    uart_tx_valid = ex_st && (ex_sa == UART_ADDR) && !halt;
    uart_tx = 8'h0;
    if (uart_tx_valid) begin
      case (ex_sa[1:0])
        2'b00: uart_tx = ex_sd[7:0];
        2'b01: uart_tx = ex_sd[15:8];
        2'b10: uart_tx = ex_sd[23:16];
        default: uart_tx = ex_sd[31:24];
      endcase
    end
  end
endmodule
`default_nettype wire
