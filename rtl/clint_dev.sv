// clint_dev.sv - memory-mapped CLINT device at 0x0200_0000 (L1).
// Slots: +0x000 msip, +0x800/+0x4000 mtimecmp_lo, +0x804/+0x4004 mtimecmp_hi,
//        +0x808/+0xBFF8 mtime_lo, +0x80C/+0xBFFC mtime_hi. mtime ticks once per
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
  input  logic [31:0] mstatus_in,  // mstatus after-MEM view (MIE/SIE bits)
  input  logic [31:0] mie_in,      // mie after MEM-stage write
  input  logic [31:0] mideleg_in,  // interrupt delegation mask after MEM-stage write
  input  logic [1:0]  priv_cur,    // current privilege (3=M, 1=S, 0=U)
`ifndef FPGA
  input  logic [31:0] mip_sw_in,   // software-set mip pending bits (except live MSI/MTI)
`endif
  output logic [31:0] ld_data,
  output logic        pending,
  output logic        timer_ready,
  output logic [31:0] cause
`ifndef FPGA
  ,output logic [31:0] mip_out
  ,output logic [63:0] mt_out
  ,output logic [63:0] cmp_out
`endif
);
  localparam logic [31:0] CLINT_BASE = 32'h0200_0000;

`ifdef FPGA
  assign ld_data = 32'h0;
  assign pending = 1'b0;
  assign timer_ready = 1'b0;
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
  wire [31:0] mip_live = ((mtie ? 32'd1 : 32'd0) << 7) |
                         ((msie ? 32'd1 : 32'd0) << 3);
  wire [31:0] mip_all  = mip_live | (mip_sw_in & 32'hFFFF_FF77);
  assign mip_out = mip_live;
  assign mt_out  = mt_next;
  assign cmp_out = {st_cmh, st_cml};
  assign timer_ready = ({st_mth, st_mtl} >= {st_cmh, st_cml});
  wire [31:0] mid     = mideleg_in;
  wire [31:0] ready   = mie_in & mip_all;
  wire [31:0] nd      = ready & ~mid;
  wire [31:0] dl      = ready & mid;
  wire [31:0] sel     = (priv_cur == 2'b11)
                      ? (((mstatus_in & 32'h0000_0008) != 0) ? (ready | dl) : 32'h0)
                      : ((((mstatus_in & 32'h0000_0008) != 0) ? nd : 32'h0) |
                         (((mstatus_in & 32'h0000_0002) != 0) ? dl : 32'h0));
  wire [31:0] sel_lsb = sel & (~sel + 32'd1);
  wire        match   = ((ea & 32'hFFFF_0000) == CLINT_BASE);

  assign pending = (sel != 0);
  assign cause   = (sel != 0) ? (32'h8000_0000 | $clog2(sel_lsb)) : 32'h0;

  always_comb begin
    ld_data = 32'h0;
    if (match) begin
      case (ea[15:0])
        16'h0000: ld_data = st_msip;
        16'h0800: ld_data = st_cml;
        16'h0804: ld_data = st_cmh;
        16'h0808: ld_data = mt_next[31:0];
        16'h080C: ld_data = mt_next[63:32];
        16'h4000: ld_data = st_cml;
        16'h4004: ld_data = st_cmh;
        16'hBFF8: ld_data = mt_next[31:0];
        16'hBFFC: ld_data = mt_next[63:32];
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
`ifdef LINUX_DEBUG
        if ((ea[15:0] == 16'h4000) || (ea[15:0] == 16'h4004) ||
            (ea[15:0] == 16'h0800) || (ea[15:0] == 16'h0804) ||
            (ea[15:0] == 16'hBFF8) || (ea[15:0] == 16'hBFFC))
          $display("DBG CLINT-W ea=%08x off=%04x val=%08x old=%08x mt=%016x cmp=%016x mtie=%d msie=%d",
                   ea, ea[15:0], wdata,
                   (ea[15:0] == 16'h4004 || ea[15:0] == 16'h0804) ? st_cmh : st_cml,
                   mt_next, {st_cmh, st_cml}, mtie, msie);
`endif
        case (ea[15:0])
          16'h0000: st_msip <= wdata & 32'h1;
          16'h0800: st_cml  <= wdata;
          16'h0804: st_cmh  <= wdata;
          16'h0808: st_mtl  <= wdata;   // direct mtime write overrides tick
          16'h080C: st_mth  <= wdata;
          16'h4000: st_cml  <= wdata;
          16'h4004: st_cmh  <= wdata;
          16'hBFF8: st_mtl  <= wdata;   // Linux mtime low half
          16'hBFFC: st_mth  <= wdata;   // Linux mtime high half
          default: begin end
        endcase
      end
    end
  end
`endif
endmodule
`default_nettype wire
