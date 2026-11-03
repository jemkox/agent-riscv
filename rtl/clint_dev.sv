// clint_dev.sv - memory-mapped CLINT device at 0x0200_0000 (L1).
// Slots: +0x000 msip, +0x800 mtimecmp_lo, +0x804 mtimecmp_hi,
//        +0x808 mtime_lo, +0x80C mtime_hi. mtime ticks once per retired
// instruction. Loads read the execute-point view (mtime includes this
// cycle's retire) so they match the ISS point-of-execution semantics.
`default_nettype none
/* verilator lint_off UNUSED */
module clint_dev (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt_in,
  input  logic        retire_en,
  input  logic        commit,      // store commit (gated by cache32: dreq+ready)
  input  logic [31:0] ea,          // effective address (load select + commit)
  input  logic [31:0] wdata,       // store data (idex sd_raw)
  input  logic [31:0] mstatus_in,  // MIE bit (after-MEM view)
  input  logic [31:0] mie_in,      // mie after MEM-stage write
  output logic [31:0] ld_data,
  output logic        pending,
  output logic [31:0] cause
`ifndef FPGA
  ,output logic [31:0] mip_out
`endif
);
  localparam logic [31:0] CLINT_BASE = 32'h0200_0000;

`ifdef FPGA
  assign ld_data = 32'h0;
  assign pending = 1'b0;
  assign cause   = 32'h0;
`else
  logic [31:0] st_msip  = 32'h0;
  logic [31:0] st_mtl   = 32'h0;
  logic [31:0] st_mth   = 32'h0;
  logic [31:0] st_cml   = 32'hFFFF_FFFF;
  logic [31:0] st_cmh   = 32'hFFFF_FFFF;

  wire [63:0] mt_next = {st_mth, st_mtl} + (retire_en ? 64'd1 : 64'd0);
  wire        mtie    = (mt_next >= {st_cmh, st_cml});
  wire        msie    = st_msip[0];
  wire [31:0] mip     = ({mtie ? 32'd1 : 32'd0} << 7) |
                        ({msie ? 32'd1 : 32'd0} << 3);
  assign mip_out = mip;
  wire [31:0] sel     = mie_in & mip;
  wire        match   = ((ea & 32'hFFFFF000) == CLINT_BASE);

  assign pending = ((mstatus_in & 32'h0000_0008) != 0) && (sel != 0);
  assign cause   = ((sel & 32'h0000_0800) != 0) ? 32'h8000_000B :
                   ((sel & 32'h0000_0080) != 0) ? 32'h8000_0007 : 32'h8000_0003;

  always_comb begin
    ld_data = 32'h0;
    if (match) begin
      case (ea[11:0])
        12'h000: ld_data = st_msip;
        12'h800: ld_data = st_cml;
        12'h804: ld_data = st_cmh;
        12'h808: ld_data = mt_next[31:0];
        12'h80C: ld_data = mt_next[63:32];
        default: ld_data = 32'h0;
      endcase
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      st_msip <= 32'h0;
      st_mtl  <= 32'h0;
      st_mth  <= 32'h0;
      st_cml  <= 32'hFFFF_FFFF;
      st_cmh  <= 32'hFFFF_FFFF;
    end else if (!halt_in) begin
      st_mtl <= st_mtl + (retire_en ? 32'd1 : 32'd0);
      if (retire_en && st_mtl == 32'hFFFF_FFFF) st_mth <= st_mth + 32'd1;
      if (commit) begin
        case (ea[11:0])
          12'h000: st_msip <= wdata & 32'h1;
          12'h800: st_cml  <= wdata;
          12'h804: st_cmh  <= wdata;
          12'h808: st_mtl  <= wdata;   // direct mtime write overrides tick
          12'h80C: st_mth  <= wdata;
          default: begin end
        endcase
      end
    end
  end
`endif
endmodule
`default_nettype wire
