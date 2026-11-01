// 32 x 32-bit register file, x0 always zero. Clocked writes; reset clears all.
module regs32 (
  input  logic        clk,
  input  logic        reset,
  input  logic [4:0]  rsel1,
  input  logic [4:0]  rsel2,
  output logic [31:0] rs1,
  output logic [31:0] rs2,
  input  logic        wena,
  input  logic [4:0]  wsel,
  input  logic [31:0] wdata
);
  logic [31:0] rf [0:31];

  assign rs1 = (rsel1 == 5'd0) ? 32'h0 : rf[rsel1];
  assign rs2 = (rsel2 == 5'd0) ? 32'h0 : rf[rsel2];

  always_ff @(posedge clk) begin
    if (reset) begin
      for (int i = 0; i < 32; i++) rf[i] <= 32'h0;
    end else if (wena && wsel != 5'd0) begin
      rf[wsel] <= wdata;
    end
  end
`ifdef FORMAL
  always_comb begin
    assert(!(wena && (wsel == 5'd0)));
    if (rsel1 == 5'd0) assert(rs1 == 32'h0);
    if (rsel2 == 5'd0) assert(rs2 == 32'h0);
  end
`endif
endmodule
