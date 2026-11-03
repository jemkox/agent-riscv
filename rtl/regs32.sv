// 32 x 32-bit register file, x0 always zero. Clocked writes; reset clears all.
module regs32 (
  input  logic        clk,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic        reset,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [4:0]  rsel1,
  input  logic [4:0]  rsel2,
  output logic [31:0] rs1,
  output logic [31:0] rs2,
  input  logic        wena,
  input  logic [4:0]  wsel,
  input  logic [31:0] wdata
`ifdef LINUX
 ,input  logic        linux_init_valid,
  input  logic [31:0] linux_init_addr
`endif
);
`ifdef FPGA
  // FPGA build: one register bank per SB_RAM40_4K half (MODE 0, zero-init).
  // rf[0] is never written (WE masked), so x0 reads back zero.
  logic [15:0] rl1, rl2, rh1, rh2;
  logic wmask;
  assign wmask = wena && (wsel != 5'd0);
  SB_RAM40_4K rlo1 (
    .RDATA(rl1), .RCLK(clk), .RCLKE(1), .RE(1), .RADDR({1'b0, rsel1}),
    .WCLK(clk), .WCLKE(1), .WE(wmask), .WADDR({1'b0, wsel}),
    .MASK(16'h0), .WDATA(wdata[15:0])
  );
  SB_RAM40_4K rlo2 (
    .RDATA(rl2), .RCLK(clk), .RCLKE(1), .RE(1), .RADDR({1'b0, rsel2}),
    .WCLK(clk), .WCLKE(1), .WE(wmask), .WADDR({1'b0, wsel}),
    .MASK(16'h0), .WDATA(wdata[15:0])
  );
  SB_RAM40_4K rhi1 (
    .RDATA(rh1), .RCLK(clk), .RCLKE(1), .RE(1), .RADDR({1'b0, rsel1}),
    .WCLK(clk), .WCLKE(1), .WE(wmask), .WADDR({1'b0, wsel}),
    .MASK(16'h0), .WDATA(wdata[31:16])
  );
  SB_RAM40_4K rhi2 (
    .RDATA(rh2), .RCLK(clk), .RCLKE(1), .RE(1), .RADDR({1'b0, rsel2}),
    .WCLK(clk), .WCLKE(1), .WE(wmask), .WADDR({1'b0, wsel}),
    .MASK(16'h0), .WDATA(wdata[31:16])
  );
  assign rs1 = {rh1, rl1};
  assign rs2 = {rh2, rl2};
`else
  logic [31:0] rf [0:31];
  assign rs1 = (rsel1 == 5'd0) ? 32'h0 : rf[rsel1];
  assign rs2 = (rsel2 == 5'd0) ? 32'h0 : rf[rsel2];

  always_ff @(posedge clk) begin
    if (reset) begin
      for (int i = 0; i < 32; i++) rf[i] <= 32'h0;
`ifdef LINUX
      rf[11] <= linux_init_valid ? linux_init_addr : 32'h0;
`endif
    end else if (wena && wsel != 5'd0) begin
      rf[wsel] <= wdata;
    end
  end
`endif
`ifdef FORMAL
  always_comb begin
    assert(!(wena && (wsel == 5'd0)));
    if (rsel1 == 5'd0) assert(rs1 == 32'h0);
    if (rsel2 == 5'd0) assert(rs2 == 32'h0);
  end
`endif
endmodule
