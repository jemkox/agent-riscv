// Differential runner: loads a program (word hex) through the mem loader port,
// runs the CPU, and prints retired instructions: "pc insn rd val st sa sd mask".
// Hex file: -DTBHEX='"f.hex"' (iverilog) or argv[1] (verilator -DVRUNTIME).
`ifdef TOPPIPE
  `define TOP top_pipe
`else
  `define TOP top_single
`endif
`default_nettype none
module run_hex ();
  logic clk = 0, reset = 1;
  logic lwe = 0, halt, wben;
  logic [31:0] lwa = 0, lwd = 0;
  logic [31:0] ex_pc, ex_insn, ex_wv;
  logic [31:0] ex_sa, ex_sd;
  logic [4:0]  ex_rd;
  logic [3:0]  ex_sbe;
  logic        ex_st;
  logic        rv_valid;

  `TOP T(.clk(clk), .reset(reset), .lwe(lwe), .lwa(lwa), .lwd(lwd),
         .halt(halt), .ex_pc(ex_pc), .ex_insn(ex_insn),
         .ex_wben(wben), .ex_rd(ex_rd), .ex_wv(ex_wv),
         .ex_st(ex_st), .ex_sa(ex_sa), .ex_sd(ex_sd), .ex_sbe(ex_sbe),
         .rv_valid(rv_valid));

  logic [31:0] prog [0:4095];
  int n, done;

  initial begin
    for (int k = 0; k < 4096; k++) prog[k] = 0;
`ifdef TBHEX
    $readmemh(`TBHEX, prog);
`else
    $readmemh("/home/jemko/agent-workspace/hdl/rv32cpu/build/p.hex", prog);
`endif
    // load phase: CPU frozen under reset, loader port pokes RAM
    reset = 1;
    for (n = 0; n < 4096; n++) begin
      lwa = n << 2; lwd = prog[n]; lwe = 1;
      #1;
      clk = 1; #1;
      clk = 0; #1;
    end
    lwe = 0;
    lwa = 0; lwd = 0;
    #1;
    clk = 1; #1;              // one reset commit: pc=0, rf clear
    clk = 0; #1;
    reset = 0;
    #1;
    // run: log feeds (instruction about to commit), then commit
    n = 0; done = 0;
    while (n < 200000 && done == 0) begin
      if (rv_valid) begin
        $display("%08x %08x %0d %08x %0d %08x %08x %0x",
                 ex_pc, ex_insn, ex_rd, wben ? ex_wv : 32'h0,
                 ex_st, ex_sa, ex_sd, ex_sbe);
        n = n + 1;
      end
      if (halt) done = 1;
      else begin
        clk = 1; #1;
        clk = 0; #1;
      end
    end
    if (!halt) $display("#NOTERM after %d instrs", n);
    $display("#SUMMARY INSN=%d HALT=%0d", n, halt ? 1 : 0);
`ifndef VRUNTIME
    $dumpfile("wave.vcd");
    $dumpvars(0, run_hex);
`endif
  end
endmodule
