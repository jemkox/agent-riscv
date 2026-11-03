// Behavioral gate for the FULL pipelined FPGA top (fpga_pipe_top, -DFPGA build):
// ROM = t07_m.hex (M-heavy directed test) baked into cache32_fpga via
// fpga_m_prog_init.sv. Prints the retire log in run_hex format so the Makefile
// gate (fpga_mgate) can cmp.py it against the ISS log for build/t07_m.bin --
// this checks every retired rd/val incl. MUL/DIV through the SB_MAC16 MDU and
// the idex_m_go retiming, not just placement/routing.
`default_nettype none
/* verilator lint_off UNUSED */
module fpga_pipe_tb();
  logic clk = 0;
  logic reset = 1;
  logic [7:0] tx = 8'h00;
  logic tx_valid = 0;
  logic halted = 0;
  int n = 0;
  int cycles = 0;

  fpga_pipe_top f(clk, reset, tx, tx_valid, halted);

  initial begin
    for (int i = 0; i < 2; i++) begin
      clk = 1; #1;
      clk = 0; #1;
    end
    reset = 0;
    #1;
    while (n < 100000) begin
      if (f.dummy_rv) begin
        $display("%08x %08x %0d %08x %0d %08x %08x %0x",
                 f.dummy_pc, f.dummy_insn, f.dummy_rd,
                 f.dummy_wben ? f.dummy_wv : 32'h0,
                 f.ex_st, f.ex_sa, f.ex_sd, f.ex_sbe);
        n = n + 1;
      end
      if (halted) break;
      clk = 1; #1;
      clk = 0; #1;
      cycles = cycles + 1;
    end
    $display("#SUMMARY INSN=%0d CYCLES=%0d HALT=%0d", n, cycles, halted);
    if (halted) $display("TEST PASSED: halted after %0d retired instrs", n);
    else $display("TEST FAILED: %0d errors (program did not halt within %0d cycles)", n, cycles);
  end
endmodule
`default_nettype wire
