// Standalone testbench for the FPGA-build MDU (rtl/mdiu_fpga.sv).
// Drives 46 MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU cases and compares
// against SV integer math. Self-checking; prints TEST PASSED / FAILED.
/* verilator lint_off TIMESCALEMOD */
module mdui_tb ();
  logic clk = 0;
  logic reset = 1;
  logic idex_valid = 0, is_m = 0, is_ill = 0, idex_done = 0, ex_stall = 0;
  logic [2:0] op = 0;
  logic [31:0] a = 0, b = 0;
  logic [31:0] tbres;
  logic tba;
  logic tbd;

  mdiu_fpga MD (.clk(clk), .reset(reset), .idex_valid(idex_valid), .is_m(is_m),
                .is_ill(is_ill), .idex_done(idex_done), .ex_stall(ex_stall),
                .op(op), .a(a), .b(b),
                .md_active(tba), .md_done_now(tbd), .result(tbres));

  localparam NC = 46;
  logic [2:0]  ops [NC];
  logic [31:0] avs [NC];
  logic [31:0] bvs [NC];
  int errors = 0;
  int done_now_seen;

  always begin clk = ~clk; #1; end

  initial begin
    $dumpfile("build/mdiu_tb.vcd");
    $dumpvars(0, mdui_tb);
    ops[0]=3'd0;  avs[0]=32'h0000_0007; bvs[0]=32'h0000_0003;
    ops[1]=3'd0;  avs[1]=32'hFFFF_FFF9; bvs[1]=32'h0000_0003; // -7*3
    ops[2]=3'd0;  avs[2]=32'h8000_0000; bvs[2]=32'hFFFF_FFFF; // INT_MIN*-1
    ops[3]=3'd0;  avs[3]=32'h8000_0000; bvs[3]=32'h0000_0003;
    ops[4]=3'd0;  avs[4]=32'hFFFF_FFFF; bvs[4]=32'hFFFF_FFFF; // -1*-1
    ops[5]=3'd0;  avs[5]=32'h1234_5678; bvs[5]=32'h9ABC_DEF0;
    ops[6]=3'd1;  avs[6]=32'h0000_0007; bvs[6]=32'h0000_0003;
    ops[7]=3'd1;  avs[7]=32'hFFFF_FFF9; bvs[7]=32'h0000_0003; // -7*3 high
    ops[8]=3'd1;  avs[8]=32'h8000_0000; bvs[8]=32'hFFFF_FFFF; // high INT_MIN*-1
    ops[9]=3'd1;  avs[9]=32'h7FFF_FFFF; bvs[9]=32'h7FFF_FFFF;
    ops[10]=3'd1; avs[10]=32'hFFFF_FFFF; bvs[10]=32'hFFFF_FFFF;
    ops[11]=3'd1; avs[11]=32'h1234_5678; bvs[11]=32'hFFFF_FF00;
    ops[12]=3'd2; avs[12]=32'hFFFF_FFF9; bvs[12]=32'hFFFF_FFFF; // -7 * u max
    ops[13]=3'd2; avs[13]=32'h8000_0000; bvs[13]=32'hFFFF_FFFF; // INT_MIN * u max
    ops[14]=3'd2; avs[14]=32'h7FFF_FFFF; bvs[14]=32'hFFFF_FFFF;
    ops[15]=3'd2; avs[15]=32'h0000_0007; bvs[15]=32'hFFFF_FFFF;
    ops[16]=3'd2; avs[16]=32'hFFFF_FFFF; bvs[16]=32'h0000_0003; // -1 * 3
    ops[17]=3'd2; avs[17]=32'h1234_5678; bvs[17]=32'h9ABC_DEF0;
    ops[18]=3'd3; avs[18]=32'hFFFF_FFFF; bvs[18]=32'hFFFF_FFFF; // u max ^2 high
    ops[19]=3'd3; avs[19]=32'h8000_0000; bvs[19]=32'h8000_0000;
    ops[20]=3'd3; avs[20]=32'h0000_0007; bvs[20]=32'h0000_0003;
    ops[21]=3'd3; avs[21]=32'h1234_5678; bvs[21]=32'h9ABC_DEF0;
    ops[22]=3'd3; avs[22]=32'h7FFF_FFFF; bvs[22]=32'h0000_0003;
    ops[23]=3'd3; avs[23]=32'h0000_0000; bvs[23]=32'h0000_0000;
    ops[24]=3'd4; avs[24]=32'h0000_0015; bvs[24]=32'h0000_0007;
    ops[25]=3'd4; avs[25]=32'hFFFF_FFEB; bvs[25]=32'h0000_0007; // -21/7 = -3
    ops[26]=3'd4; avs[26]=32'h0000_0015; bvs[26]=32'hFFFF_FFF9; // 21/-7 = -3
    ops[27]=3'd4; avs[27]=32'h8000_0000; bvs[27]=32'hFFFF_FFFF; // INT_MIN/-1
    ops[28]=3'd4; avs[28]=32'h0000_0005; bvs[28]=32'h0000_0000; // x/0 = -1
    ops[29]=3'd4; avs[29]=32'hFFFF_FFFF; bvs[29]=32'h0000_0001;
    ops[30]=3'd4; avs[30]=32'h8000_0000; bvs[30]=32'h0000_0002;
    ops[31]=3'd4; avs[31]=32'h7FFF_FFFF; bvs[31]=32'hFFFF_FFFF; // max/-1
    ops[32]=3'd5; avs[32]=32'hFFFF_FFFF; bvs[32]=32'h0000_0002; // u max / 2
    ops[33]=3'd5; avs[33]=32'h8000_0000; bvs[33]=32'h0000_0002;
    ops[34]=3'd5; avs[34]=32'h0000_0005; bvs[34]=32'h0000_0000; // /0 = -1
    ops[35]=3'd5; avs[35]=32'h0000_0015; bvs[35]=32'h0000_0007;
    ops[36]=3'd5; avs[36]=32'hABCD_EF01; bvs[36]=32'h0000_1234;
    ops[37]=3'd5; avs[37]=32'h8000_0000; bvs[37]=32'hFFFF_FFFF;
    ops[38]=3'd6; avs[38]=32'h0000_0015; bvs[38]=32'h0000_0007;
    ops[39]=3'd6; avs[39]=32'hFFFF_FFEB; bvs[39]=32'h0000_0007; // -21%7 = 0
    ops[40]=3'd6; avs[40]=32'h0000_0015; bvs[40]=32'hFFFF_FFF9; // 21%-7 = 7
    ops[41]=3'd6; avs[41]=32'h8000_0000; bvs[41]=32'hFFFF_FFFF; // INT_MIN%-1 = 0
    ops[42]=3'd6; avs[42]=32'h0000_0005; bvs[42]=32'h0000_0000; // x%0 = x
    ops[43]=3'd6; avs[43]=32'hFFFF_FFFF; bvs[43]=32'hFFFF_FFFC; // -1%-4 = -1
    ops[44]=3'd7; avs[44]=32'hABCD_EF01; bvs[44]=32'h0000_1234;
    ops[45]=3'd7; avs[45]=32'h8000_0000; bvs[45]=32'h0000_0000; // x%0 = x
    reset = 1;
    #7;
    reset = 0;
    #1;
    for (int i = 0; i < NC; i = i + 1) begin
      op = ops[i]; a = avs[i]; b = bvs[i];
      is_m = 1; idex_valid = 1; is_ill = 0; idex_done = 0; ex_stall = 0;
      #2;                          // one full clock at issue (posedge at odd us)
      idex_valid = 0; is_m = 0;
      done_now_seen = 0;
      for (int w = 0; w < 80 && !done_now_seen; w = w + 1) begin
        #2;
        if (tbd) done_now_seen = 1;
      end
      #2;                          // result latched at the done edge
      if (tbres !== expected(ops[i], a, b)) begin
        errors = errors + 1;
        $display("CASE %0d op=%0d a=%08x b=%08x got=%08x want=%08x",
                 i, ops[i], a, b, tbres, expected(ops[i], a, b));
      end
    end
    if (errors == 0) $display("TEST PASSED (46 cases)");
    else             $display("TEST FAILED: %0d errors", errors);
    $finish;
  end

  function logic [31:0] expected (logic [2:0] o, logic [31:0] x, logic [31:0] y);
    logic [63:0] xs, ys, xu, yu, pr;
    logic [31:0] xa, ya, q, r;
    begin
      xs = {{32{x[31]}}, x}; ys = {{32{y[31]}}, y};
      xu = {32'h0, x};       yu = {32'h0, y};
      expected = 32'h0;
      case (o)
        3'd0: begin pr = xu * yu;          expected = pr[31:0]; end
        3'd1: begin pr = xs * ys;          expected = pr[63:32]; end
        3'd2: begin pr = xs * yu;          expected = pr[63:32]; end
        3'd3: begin pr = xu * yu;          expected = pr[63:32]; end
        3'd4: begin
          if (y == 32'h0) expected = 32'hFFFF_FFFF;
          else begin
            xa = x[31] ? (~x + 32'h1) : x;
            ya = y[31] ? (~y + 32'h1) : y;
            q = xa / ya;
            expected = (x[31] ^ y[31]) ? (~q + 32'h1) : q;
          end
        end
        3'd5: begin
          if (y == 32'h0) expected = 32'hFFFF_FFFF;
          else expected = xu / yu;
        end
        3'd6: begin
          if (y == 32'h0) expected = x;
          else begin
            xa = x[31] ? (~x + 32'h1) : x;
            ya = y[31] ? (~y + 32'h1) : y;
            r = xa % ya;
            expected = x[31] ? (~r + 32'h1) : r;
          end
        end
        3'd7: begin
          if (y == 32'h0) expected = x;
          else expected = xu % yu;
        end
        default: expected = 32'h0;
      endcase
    end
  endfunction
endmodule
