// M7 runner: loads a program hex through the loader port, runs top_pipe with cache/MMIO,
// prints memory-mapped UART bytes, and prints a cycle/instruction summary.
`ifdef TOPPIPE
  `define TOP top_pipe
`else
  `define TOP top_single
`endif
`default_nettype none
module run_mmio ();
  /* verilator lint_off UNUSED */
  /* verilator lint_off WIDTHTRUNC */
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

  `TOP T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
         .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
         .ex_wben(wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
         .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_sbe(ex_sbe),
         .rv_valid(rv_valid), .bp_branches(bp_branches),
         .bp_taken_preds(bp_taken_preds), .bp_mispreds(bp_mispreds));

  localparam PROG_WORDS = 1048576; /* 4 MB of word slots: covers a 0x100000 data blob */
  localparam [31:0] UART_ADDR = 32'h1000_0000;
  logic [31:0] prog [0:PROG_WORDS-1];
  int n, done, cycles, uart_bytes, max_insns, dbg_on = 0, n_dbg = 0;

  initial begin
    $readmemh("build/m7/p.hex", prog);
    reset = 1;
    for (int i = 0; i < PROG_WORDS; i++) begin
      if (prog[i] != 0) begin
        lwa = i << 2; lwd = prog[i]; lwe = 1;
        #1;
        clk = 1; #1;
        clk = 0; #1;
      end
    end
    lwe = 0;
    lwa = 0; lwd = 0;
    #1;
    clk = 1; #1;
    clk = 0; #1;
    reset = 0;
    dbg_on = 1;
    #1;

    n = 0; done = 0; cycles = 0; uart_bytes = 0; max_insns = 20000000;
    while (n < max_insns && done == 0) begin
      if (rv_valid) begin
        if (ex_st && (ex_sa == UART_ADDR) && ex_sbe[0]) begin
          $write("%c", ex_sd[7:0]);
          $display("#UBYTE %02x %c", ex_sd[7:0], ex_sd[7:0]);
          uart_bytes = uart_bytes + 1;
        end
        n = n + 1;
      end
      if ((dbg_on && n_dbg < 999999) || (cycles != 0 && (cycles % 4000000) == 0)) begin
        $display("#DBG c=%0d halt=%0d ex_pc=%08x ex_insn=%08x ex_st=%0d ex_sa=%08x ex_rd=%0d ex_wv=%08x rv=%0d",
                 cycles, halt, ex_pc, ex_insn, ex_st, ex_sa, ex_rd, ex_wv, rv_valid);
        n_dbg = n_dbg + 1;
      end
      if (halt) done = 1;
      else begin
        clk = 1; #1;
        clk = 0; #1;
        cycles = cycles + 1;
      end
    end
    if (!halt) $display("#NOTERM after %d instrs", n);
    $display("#UART_BYTES=%0d", uart_bytes);
    $display("#M7SUM INSN=%0d CYCLES=%0d IPC=%0.3f HALT=%0d", n, cycles, (cycles != 0) ? real'(n) / cycles : 0.0, halt ? 1 : 0);
    $display("#BPSTAT BR=%0d TAKEN=%0d MISPRED=%0d ACC=%0.3f", bp_branches, bp_taken_preds, bp_mispreds,
             (bp_branches != 0) ? 100.0 - (100.0 * real'(bp_mispreds)) / real'(bp_branches) : 0.0);
    $display("");
`ifndef VRUNTIME
    $dumpfile("wave.vcd");
    $dumpvars(0, run_mmio);
`endif
  end
endmodule

