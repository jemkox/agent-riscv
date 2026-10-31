module probe3 ();
  logic clk = 0, lwe = 1;
  logic [31:0] lwa = 0, lwd = 0;
  logic [31:0] id, ia, ld, la;
  mem32 M(.clk(clk), .ia(ia), .id(id), .la(la), .ld(ld),
          .sw(0), .sa(0), .sd(0), .sbe(0),
          .lwe(lwe), .lwa(lwa), .lwd(lwd));
  initial begin
    lwa = 0; lwd = 32'h42; ia = 0; la = 0;
    clk = 1; #1;
    clk = 0; #1;
    clk = 1; #1;
    clk = 0; #1;
    #1;
    $display("#RAM0=%08x", M.ram[0]);
  end
endmodule
