module probe4 ();
  logic clk = 0;
  logic [31:0] ram[0:1] = {32'h0, 32'h0};
  initial begin
    clk = 1; #1;
    clk = 0; #1;
    clk = 1; #1;
    clk = 0; #1;
    #1;
    $display("#RAM0=%08x", ram[0]);
  end
  always_ff @(posedge clk) begin
    ram[0] <= 32'h42;
  end
endmodule
