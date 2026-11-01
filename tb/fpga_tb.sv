// FPGA proof self-check: fixed ROM program stores to RAM, loads back, sends one UART byte.
/* verilator lint_off UNUSED */
module fpga_tb();
  logic clk = 0;
  logic reset = 1;
  logic [7:0] tx = 8'h00;
  logic tx_valid = 0;
  logic halted = 0;
  int tx_count = 0;
  int errs = 0;
  int got0 = -1;

  fpga_top f(clk, reset, tx, tx_valid, halted);

  initial begin
    $dumpfile("build/fpga.vcd");
    $dumpvars(0, fpga_tb);
    for (int i = 0; i < 2; i++) begin
      clk = 1; #1;
      clk = 0; #1;
    end
    reset = 0;
    for (int step = 0; step < 40 && !halted; step++) begin
      clk = 1; #1;
      if (tx_valid) begin
        if (tx_count == 0) got0 = int'(tx);
        tx_count++;
      end
      clk = 0; #1;
    end
    if (tx_count != 1 || got0 != 32'h41 || !halted) errs++;
    if (f.dmem[0] != 32'h41) errs++;
    if (f.regs[1] != 32'h41 || f.regs[4] != 32'h41 || f.regs[7] != 32'h82) errs++;
    if (errs != 0) $display("DEBUG tx_count=%0d got0=%0d halted=%0b dmem0=%08x r1=%08x r4=%08x r7=%08x", tx_count, got0, halted, f.dmem[0], f.regs[1], f.regs[4], f.regs[7]);
    if (errs == 0) $display("TEST PASSED");
    else $display("TEST FAILED: %0d errors", errs);
  end
endmodule
