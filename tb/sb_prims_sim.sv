// Simulation stubs for FPGA library primitives (used ONLY by the Verilator
// behavioral gates that compile the -DFPGA source, e.g. fpga_mgate).
// Not used by yosys/nextpnr (the real SB_RAM40_4K comes from the toolchain).
//
// SB_RAM40_4K: implemented for the MODE 0 array mode used by rtl/regs32.sv
// (RADDR/WADDR 6-bit, 16-bit cells, MASK bits are NOT written). Read returns
// the pre-write value on the same clock, like the non-FPGA regs32 does.
`default_nettype none
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSED */
module SB_RAM40_4K (
  output logic [15:0] RDATA,
  input  logic        RCLK, RCLKE, RE,
  input  logic [5:0]  RADDR,
  input  logic        WCLK, WCLKE, WE,
  input  logic [5:0]  WADDR,
  input  logic [15:0] WDATA,
  input  logic [15:0] MASK
);
  localparam int INIT = 0;
  localparam int READ_MODE = 0;
  localparam int WRITE_MODE = 0;
  logic [15:0] mem [0:63];

  logic [15:0] rdata;

  initial begin
    rdata = 16'h0;
    for (int i = 0; i < 64; i++) mem[i] = 16'h0;
  end

  assign RDATA = rdata;

  always @(posedge WCLK) begin
    if (WCLKE && WE) mem[WADDR] <= (mem[WADDR] & MASK) | (WDATA & ~MASK);
  end

  always @(posedge RCLK) begin
    rdata <= mem[RADDR];
  end
endmodule
`default_nettype wire
