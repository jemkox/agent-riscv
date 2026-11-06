// Differential runner: loads a program (word hex), runs, then dumps the
// begin_signature..end_signature region one 32-bit little-endian word per line.
// The Verilator build defines TBHEX, SIGCFG and SIGOUT absolute paths.
// SIGCFG file: two whitespace-separated hex numbers: begin end.
`ifndef TOPPIPE
  `define TOPPIPE
`endif
`ifdef TOPPIPE
  `define TOP top_pipe
`else
  `define TOP top_single
`endif
`default_nettype none
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSED */
/* verilator lint_off UNUSEDSIGNAL */
module run_hex ();
  logic clk = 0, reset = 1;
  logic lwe = 0, halt, wben;
  logic [31:0] lwa = 0, lwd = 0;
  logic [31:0] ex_pc, ex_insn, ex_wv;
  logic [31:0] ex_sa, ex_sd;
  /* verilator lint_off UNUSED */
  logic [31:0] ex_ea;
  logic [31:0] linux_dtb_addr = 32'h83e0_0000;
  logic uart_rx_ready = 0;
  logic [7:0] uart_rx_in = 0;
  logic uart_tx_valid = 0;
  logic [7:0] uart_tx_out = 0;
  logic uart_rx_pending = 0;
  logic uart_tx_ready = 0;
  /* verilator lint_on UNUSED */
  /* verilator lint_off UNUSEDSIGNAL */
  logic [4:0]  ex_rd;
  logic [3:0]  ex_sbe;
  logic        ex_st;
  logic [31:0] bp_branches, bp_taken_preds, bp_mispreds;
  /* verilator lint_on UNUSEDSIGNAL */
  logic        rv_valid;

`ifdef LINUX
  `TOP T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
         .linux_dtb_addr(linux_dtb_addr),
         .uart_rx_ready(uart_rx_ready), .uart_rx_in(uart_rx_in),
         .uart_tx_valid(uart_tx_valid), .uart_tx_out(uart_tx_out),
         .uart_rx_pending(uart_rx_pending), .uart_tx_ready(uart_tx_ready),
         .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
         .ex_wben(wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
         .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_ea(ex_ea), .ex_sbe(ex_sbe),
         .rv_valid(rv_valid), .bp_branches(bp_branches),
         .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));
`else
  `TOP T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
         .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
         .ex_wben(wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
         .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_ea(ex_ea), .ex_sbe(ex_sbe),
         .rv_valid(rv_valid), .bp_branches(bp_branches),
         .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));
`endif

  logic [31:0] prog [0:1048575];  // 4 MB program/data image
  int n, done, cycles;

`ifndef MAX_INSNS
  `define MAX_INSNS 1000000
`endif
`ifndef MAXCYCLES
  `define MAXCYCLES 20000000
`endif

  initial begin
    for (int k = 0; k < 1048576; k++) prog[k] = 0;
`ifdef TBHEX
    $readmemh(`TBHEX, prog);
`else
    $display("ERROR: TBHEX is not defined.");
`ifdef VERILATOR
    $fatal(1, "ERROR: TBHEX is not defined.");
`else
    $stop;
`endif
`endif
    reset = 1;
    for (n = 0; n < 1048576; n++) begin
`ifdef HIGH_PC
      lwa = 32'h8000_0000 + (32'(n) << 2); lwd = prog[n]; lwe = 1;
`else
      lwa = n << 2; lwd = prog[n]; lwe = 1;
`endif
      #1;
      clk = 1; #1;
      clk = 0; #1;
    end
    lwe = 0;
    lwa = 0; lwd = 0;
    #1;
    clk = 1; #1;
    clk = 0; #1;
    reset = 0;
    #1;
    n = 0; done = 0; cycles = 0;
    while (n < `MAX_INSNS && done == 0 && cycles < `MAXCYCLES) begin
      if (rv_valid) n = n + 1;
`ifdef DBG
      if (rv_valid) $display("#I %08x %08x", ex_pc, ex_insn);
`endif
      if (halt) done = 1;
      else begin
        clk = 1; #1;
        clk = 0; #1;
        cycles = cycles + 1;
      end
    end
    if (done == 0) $display("#NOTERM after %0d instrs %0d cycles", n, cycles);
    else begin
`ifdef SIGCFG
      dump_sig();
`else
      $display("#SUMMARY INSN=%0d CYCLES=%0d IPC=%0.3f HALT=%0d", n, cycles,
               (cycles != 0) ? real'(n) / cycles : 0.0, halt ? 1 : 0);
`endif
    end
`ifndef VRUNTIME
    $dumpfile("wave.vcd");
    $dumpvars(0, run_hex);
`endif
  end

  function void dump_sig();
    int cfg, out;
    bit [31:0] sb, se;
    cfg = $fopen(`SIGCFG, "r");
    if (cfg == 0) begin
      $display("#NO_SIGCFG %0s", `SIGCFG);
      return;
    end
    if ($fscanf(cfg, "%x %x", sb, se) != 2) begin
      $display("#BAD_SIGCFG");
      return;
    end
    out = $fopen(`SIGOUT, "w");
    if (out == 0) begin
      $display("#NO_SIGOUT %0s", `SIGOUT);
      return;
    end
    $display("#SIG %08x %08x", sb, se);
    if ((sb & 3) != 0 || (se & 3) != 0) begin
      $display("#BAD_ALIGN");
      return;
    end
    if ((se & 32'h3fff_ffff) < (sb & 32'h3fff_ffff)) begin
      $display("#BAD_ORDER");
      return;
    end
    for (int a = sb; a < se; a += 4) begin
`ifdef LINUX
      $fwrite(out, "%08x\n", T.MM.rw[(a >> 2) & 32'h00ff_ffff]);
`else
      $fwrite(out, "%08x\n", T.MM.rw[(a >> 2) & 32'h0000_ffff]);
`endif
    end
    $display("#SIGWROTE %0d", (se - sb) / 4);
  endfunction
endmodule
