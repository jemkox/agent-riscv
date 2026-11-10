module probe;
`ifdef FOO
  localparam int A = BAR;
`else
  localparam int A = 7;
`endif
localparam int B = BAR;
int y[8];
always begin y[A]=B; end
endmodule
