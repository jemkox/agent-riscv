// FPGA cache32: direct RAM inference (SB_RAM40_4K) with synchronous reads.
// One read port and one write port per 16-bit half array; word arrays indexed
// by word address (no arbitrary-offset byte arrays).
`default_nettype none
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSED */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
module cache32 (
  input  logic        clk,
  input  logic        reset,
  input  logic        halt,
  input  logic        lwe,
  input  logic [31:0] lwa,
  input  logic [31:0] lwd,
  input  logic [31:0] pc_if,
  output logic [31:0] fetch_insn,
  output logic        fetch_ready,
  input  logic        idex_valid,
  input  logic        idex_ld,
  input  logic        idex_st,
  input  logic [31:0] ea,
  input  logic [31:0] sd_raw,
  input  logic [1:0]  ssz,
  output logic [31:0] ld_raw,
  output logic        mem_ready,
  output logic        clint_commit,
  input  logic [31:0] clint_ld_in
);
  localparam logic [31:0] UART_ADDR = 32'h1000_0000;

  assign clint_commit = 1'b0;   // no CLINT in the FPGA build

  (* BRAM = 1 *) logic [15:0] ic_lo [0:127];
  (* BRAM = 1 *) logic [15:0] ic_hi [0:127];
  (* BRAM = 1 *) logic [15:0] dc_lo [0:127];
  (* BRAM = 1 *) logic [15:0] dc_hi [0:127];

`ifdef FPGA
`include "fpga_prog_init.sv"
`endif

  logic [15:0] ic_rd_lo, ic_rd_hi, dc_rd_lo, dc_rd_hi, dc_rd0_lo, dc_rd0_hi;
  logic [6:0]  pc_idx, ea_idx, lw_idx, if_issue, if_padr, dc_padr, st_padr;
  logic [6:0]  dc_issue_addr;
  logic        dc_issue;
  logic [1:0]  off2, dc_poff, st_poff;
  logic        dreq, uart_load, uart_store, st_req, ld_req;
  logic        st_now, st_write0, st_write1, st_p2, cross_st;
  logic        if_ready, ld_ok, ld_issue1, ld_issue2;
  logic        st_pend, if_pend, dc_pend, dc_ph;
  logic [3:0]  dbe, sbe_all;
  logic [31:0] dwd;
  logic [6:0]  wad;
  logic [63:0] sd_shift, raw_comb;
  logic [31:0] rd0, rd1;

  assign pc_idx = pc_if[8:2];
  assign ea_idx = ea[8:2];
  assign lw_idx = lwa[8:2];

  always_comb begin
    dreq        = idex_valid && (idex_ld || idex_st) && !reset && !halt && !lwe;
    uart_load   = dreq && idex_ld && (ea == UART_ADDR);
    uart_store  = dreq && idex_st && (ea == UART_ADDR);
    st_req      = dreq && idex_st && !uart_store;
    ld_req      = dreq && idex_ld && !uart_load;
    off2        = ea[1:0];

    st_now      = st_req && !st_pend;
    cross_st    = st_req && ((ssz == 2'b10 && off2 != 0) || (ssz == 2'b01 && off2 == 2'b11));
    st_write0   = st_now && !cross_st;
    st_write1   = st_now && cross_st;
    st_p2       = st_pend && ((st_padr + 7'h1) == ea_idx);

    case (ssz)
      2'b00: sbe_all = 4'b0001;
      2'b01: sbe_all = 4'b0011;
      2'b10: sbe_all = 4'b1111;
      default: sbe_all = 4'b0000;
    endcase
    sd_shift = { sd_raw, 32'h0 } << { off2, 3'b000 };

    if_ready    = if_pend && (if_padr == pc_idx);
    if_issue    = if_ready ? (pc_idx + 7'h1) : pc_idx;
    fetch_ready = if_ready;
    fetch_insn  = { ic_rd_hi, ic_rd_lo };

    ld_issue1   = ld_req && !dc_pend;
    ld_issue2   = dc_pend && (dc_padr == ea_idx) && (dc_poff == off2) &&
                  (dc_ph == 1'b0) && (off2 != 2'b00);
    dc_issue    = ld_issue1 || ld_issue2;
    dc_issue_addr = ld_issue2 ? (ea_idx + 7'h1) : ea_idx;
    ld_ok       = dc_pend && (dc_padr == ea_idx) && (dc_poff == off2) &&
                  (off2 == 2'b00 || dc_ph == 1'b1);

    rd0         = { dc_rd0_hi, dc_rd0_lo };
    rd1         = { dc_rd_hi, dc_rd_lo };
    raw_comb    = (off2 == 2'b00) ? { 32'h0, rd1 } : ({ rd1, rd0 } >> { off2, 3'b000 });
    ld_raw      = raw_comb[31:0];

    dbe = 4'b0000; dwd = 32'h0; wad = 7'h0;
    if (lwe) begin
      dbe = 4'b1111; dwd = lwd; wad = lw_idx;
    end else if (st_write0 || st_write1) begin
      dbe = sbe_all << off2;
      dwd = sd_shift[31:0];
      wad = ea_idx;
    end else if (st_p2) begin
      dbe = sbe_all >> (4'd4 - { 2'b00, st_poff });
      dwd = sd_shift[63:32];
      wad = st_padr + 7'h1;
    end

    mem_ready = (!dreq) || uart_load || uart_store || ld_ok ||
                st_write0 || st_p2;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      if_pend <= 1'b0;
      dc_pend <= 1'b0;
      st_pend <= 1'b0;
    end else begin
      if_padr   <= if_issue;
      if_pend   <= 1'b1;
      ic_rd_lo  <= ic_lo[if_issue];
      ic_rd_hi  <= ic_hi[if_issue];

      if (ld_issue2) begin
        dc_rd0_lo <= dc_rd_lo;
        dc_rd0_hi <= dc_rd_hi;
      end

      if (ld_issue1 || ld_issue2) begin
        dc_rd_lo  <= dc_lo[dc_issue_addr];
        dc_rd_hi  <= dc_hi[dc_issue_addr];
        dc_padr   <= ea_idx;
        dc_poff   <= off2;
        dc_ph     <= ld_issue2;
        dc_pend   <= 1'b1;
      end else if (ld_ok) begin
        dc_pend   <= 1'b0;
      end

      st_pend <= st_write1;
      if (st_write1) begin
        st_padr <= ea_idx;
        st_poff <= off2;
      end
    end

    if (lwe) begin
      ic_lo[lw_idx] <= lwd[15:0];
      ic_hi[lw_idx] <= lwd[31:16];
    end
    if (dbe[0]) dc_lo[wad] <= dwd[7:0];
    if (dbe[1]) dc_lo[wad] <= dwd[15:8];
    if (dbe[2]) dc_hi[wad] <= dwd[23:16];
    if (dbe[3]) dc_hi[wad] <= dwd[31:24];
  end
endmodule
`default_nettype wire
