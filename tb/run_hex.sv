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
  logic [4:0]  ex_rd;
  logic [3:0]  ex_sbe;
  logic        ex_st;
  logic        rv_valid;
  logic [31:0] bp_branches, bp_taken_preds, bp_mispreds;

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

  logic [31:0] prog [0:4095];
  int n, done, cycles;

  initial begin
    for (int k = 0; k < 4096; k++) prog[k] = 0;
`ifdef TBHEX
    $readmemh(`TBHEX, prog);
`else
    $display("ERROR: TBHEX is not defined. Verilator builds pass -DTBHEX=\"$(B)/p.hex\"; Icarus builds pass the explicit $(B)/<test>.hex path.");
`ifdef VERILATOR
    $fatal(1, "ERROR: TBHEX is not defined.");
`else
    $stop;
`endif
`endif
    // load phase: CPU frozen under reset, loader port pokes RAM
    reset = 1;
    for (n = 0; n < 4096; n++) begin
`ifdef HIGH_PC
      lwa = 32'h8000_0000 + (n << 2); lwd = prog[n]; lwe = 1;
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
    clk = 1; #1;              // one reset commit: pc=0 (or pc=0x80000000 under LINUX), rf clear
    clk = 0; #1;
    reset = 0;
    #1;
    // run: log feeds (instruction about to commit), then commit
    n = 0; done = 0; cycles = 0;
    while (n < 200000 && done == 0 && cycles < 4000000) begin
`ifdef TLBT
      $display("@TLB %0d v=%b hit_i=%b hit_d=%b act=%b walk_i=%b walk_d=%b pa_d=%h paddr=%h wa=%h raw=%h lraw=%h inj=%b ea=%h aex=%h exmem_ea=%h st=%b ms=%b mp=%b amo=%b dcause=%h ram8k=%h",
               cycles, T.idex_valid, T.mm_hit_i, T.mm_hit_d, T.mm_act, T.mm_walk_i, T.mm_walk_d,
               T.mm_pa_d, T.mm_paddr, T.mm_wa, T.ldx_raw, T.exmem_ld_raw, T.mm_inject,
               T.idex_ea, T.a_ex, T.exmem_ea, T.stall, T.m_stall, T.mem_pend, T.ce_amo, T.mm_dcause,
               T.MM.rw[32'h8000]);
`endif
      if (rv_valid) begin
        $display("%08x %08x %0d %08x %0d %08x %08x %0x",
                 ex_pc, ex_insn, ex_rd, wben ? ex_wv : 32'h0,
                 ex_st, ex_sa, ex_sd, ex_sbe);
        n = n + 1;
      end
      if (halt) begin
`ifdef SCDBG2
        $display("@RAMPA w_10000=%08x w_20000=%08x w_30000=%08x w_9140=%08x w_6000=%08x w_40000=%08x w_50000m=%08x w_9000=%08x",
                 T.MM.rw[32'h10000/4], T.MM.rw[32'h20000/4], T.MM.rw[32'h30000/4],
                 T.MM.rw[32'h9140/4], T.MM.rw[32'h6000/4], T.MM.rw[32'h3FFF0/4],
                 T.MM.rw[32'h10000/4], T.MM.rw[32'h9000/4]);
`endif
        done = 1;
      end
      else begin
        clk = 1; #1;
        clk = 0; #1;
        cycles = cycles + 1;
      end
    end
    if (!halt) $display("#NOTERM after %d instrs", n);
    $display("#SUMMARY INSN=%0d CYCLES=%0d IPC=%0.3f HALT=%0d", n, cycles, (cycles != 0) ? real'(n) / cycles : 0.0, halt ? 1 : 0);
    $display("#BPSTAT BR=%0d TAKEN=%0d MISPRED=%0d ACC=%0.3f", bp_branches, bp_taken_preds, bp_mispreds,
             (bp_branches != 0) ? 100.0 - (100.0 * real'(bp_mispreds)) / real'(bp_branches) : 0.0);
`ifndef VRUNTIME
    $dumpfile("wave.vcd");
    $dumpvars(0, run_hex);
`endif
  end
endmodule
