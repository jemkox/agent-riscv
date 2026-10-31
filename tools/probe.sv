module probe (
  input  logic clk,
  input  logic wena,
  input  logic [31:0] wdata,
  output logic [31:0] out
);
  logic [31:0] v;
  always @(posedge clk) begin
    if (wena) v <= wdata;
  end
  assign out = v;
endmodule
