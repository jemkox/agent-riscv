module probe2 ();
  logic clk = 0;
  logic [31:0] a = 0;
  int n = 0;
  always_ff @(posedge clk) a <= 32'h42;
  initial begin
    for (n = 0; n < 3; n++) begin
      clk = 1; #1;
      clk = 0; #1;
    end
    $display("#A=%08x", a);
  end
endmodule
