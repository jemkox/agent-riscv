// Real direct-mapped I/D caches over a backing RAM.
// ic_data/dc_data hold cache lines; tag/valid arrays are RAM-friendly.
`default_nettype none
/* verilator lint_off UNUSED */
/* verilator lint_off BLKSEQ */
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
  output logic        mem_ready
);
`ifdef CACHE_LAT
  localparam int LAT = `CACHE_LAT;
`else
  localparam int LAT = 1;
`endif
`ifdef FPGA
  localparam int BACK_WORDS = 256;
  localparam int IC_LINES   = 16;
  localparam int DC_LINES   = 16;
`else
`ifdef SMALL_CACHE
  localparam int BACK_WORDS = 16;
  localparam int IC_LINES   = 4;
  localparam int DC_LINES   = 4;
`else
`ifdef DOOM_BIG
  localparam int BACK_WORDS = 8 * 1024 * 1024;  // 32 MB for the Doom testbench
  localparam int IC_LINES   = 1024;
  localparam int DC_LINES   = 1024;
`else
  localparam int BACK_WORDS = 65536;
  localparam int IC_LINES   = 1024;
  localparam int DC_LINES   = 1024;
`endif
`endif
`endif
  localparam int BACK_BYTES = BACK_WORDS * 4;
  localparam int BACK_MASK  = BACK_BYTES - 1;
  localparam int IC_MASK    = IC_LINES - 1;
  localparam int DC_MASK    = DC_LINES - 1;
  localparam int LOGIC      = $clog2(IC_LINES);
  localparam int LOGDC      = $clog2(DC_LINES);
  localparam int READY_AT   = (LAT > 1) ? (LAT - 1) : 0;
  localparam int LINE_BYTES = 16;
  localparam int LINE_SHIFT = 4;

  (* BRAM = 1 *) logic [7:0] ram [0:BACK_BYTES-1];
  (* BRAM = 1 *) logic [7:0] ic_data [0:IC_LINES*LINE_BYTES-1];
  (* BRAM = 1 *) logic [7:0] dc_data [0:DC_LINES*LINE_BYTES-1];
  (* BRAM = 1 *) logic [31:0] ic_tag [0:IC_LINES-1];
  (* BRAM = 1 *) logic [31:0] dc_tag [0:DC_LINES-1];
  (* BRAM = 1 *) logic [31:0] ic_ep  [0:IC_LINES-1];
  (* BRAM = 1 *) logic [31:0] dc_ep  [0:DC_LINES-1];
  logic [31:0] epoch = 32'd1;
  logic        ic_pending = 1'b0;
  logic        dc_pending = 1'b0;
  logic [31:0] ic_ptag = 32'h0;
  logic [31:0] dc_ptag = 32'h0;
  int ic_count = 0;
  int dc_count = 0;
  int i_idx, i_tag, i_mbase;
  int d_idx, d_tag, d_off, d_cache_base, sb;
  logic ic_hit, dc_hit, ic_p_ready, dc_p_ready, dreq, uart_store, uart_load;
  logic dc_ready_now, ic_ready_now, dc_cross_ready;
`ifdef DOOM_BIG
  localparam logic [31:0] UART_ADDR = 32'h1FF0_0000; /* above the WAD blob */
`else
  localparam logic [31:0] UART_ADDR = 32'h1000_0000;
`endif

  function [31:0] rbwb;
    input int addr;
    int b;
    b = addr & BACK_MASK;
    rbwb = { ram[(b + 3) & BACK_MASK], ram[(b + 2) & BACK_MASK],
             ram[(b + 1) & BACK_MASK], ram[b & BACK_MASK] };
  endfunction

  function [31:0] rb_ic;
    input [31:0] addr;
    int base, off;
    base = ((addr >> LINE_SHIFT) & IC_MASK) * LINE_BYTES;
    off  = addr & (LINE_BYTES - 1);
    rb_ic = { ic_data[base + off + 3], ic_data[base + off + 2],
              ic_data[base + off + 1], ic_data[base + off] };
  endfunction

  function [31:0] rb_dc;
    input [31:0] addr;
    int base, off;
    base = ((addr >> LINE_SHIFT) & DC_MASK) * LINE_BYTES;
    off  = addr & (LINE_BYTES - 1);
    rb_dc = { dc_data[base + off + 3], dc_data[base + off + 2],
              dc_data[base + off + 1], dc_data[base + off] };
  endfunction

  always_comb begin
    i_idx  = (pc_if >> LINE_SHIFT) & IC_MASK;
    i_tag  = pc_if >> (LOGIC + LINE_SHIFT);
    i_mbase = pc_if & 32'hFFFFFFF0;
    d_idx  = (ea >> LINE_SHIFT) & DC_MASK;
    d_tag  = ea >> (LOGDC + LINE_SHIFT);
    d_off  = ea & (LINE_BYTES - 1);
    d_cache_base = d_idx * LINE_BYTES + d_off;

    ic_hit = (ic_ep[i_idx] == epoch) && (ic_tag[i_idx] == i_tag);
    dc_hit = (dc_ep[d_idx] == epoch) && (dc_tag[d_idx] == d_tag);
    dreq = idex_valid && (idex_ld || idex_st) && !reset && !halt && !lwe;
    uart_store = dreq && idex_st && (ea == UART_ADDR);
    uart_load  = dreq && idex_ld && (ea == UART_ADDR);
    dc_cross_ready = dreq && (d_off > 12);

    ic_p_ready = ic_pending && (ic_ptag == i_tag) && (ic_count >= READY_AT);
    dc_p_ready = dc_pending && (dc_ptag == d_tag) && (dc_count >= READY_AT);

    ic_ready_now = ic_hit || ic_p_ready || (LAT == 1);
    dc_ready_now = dc_hit || dc_p_ready || dc_cross_ready ||
                   uart_store || uart_load || (LAT == 1);

    fetch_ready = (reset || halt) ? 1'b1 : ic_ready_now;
    fetch_insn  = ic_ready_now ? (ic_hit ? rb_ic(pc_if) : rbwb(pc_if)) : 32'h0;
    mem_ready   = (reset || halt) ? 1'b1 : (!dreq || dc_ready_now);
    ld_raw = dc_ready_now ?
             (uart_load ? 32'h0 :
              ((dc_hit && (d_off <= 12)) ? rb_dc(ea) : rbwb(ea))) :
             32'h0;
  end

  always_ff @(posedge clk) begin
    if (lwe) begin
      sb = lwa & BACK_MASK;
      ram[sb]                       = lwd[7:0];
      ram[(sb + 1) & BACK_MASK]     = lwd[15:8];
      ram[(sb + 2) & BACK_MASK]     = lwd[23:16];
      ram[(sb + 3) & BACK_MASK]     = lwd[31:24];
    end

    if (reset) begin
      for (int k = 0; k < IC_LINES; k++) begin
        ic_ep[k] = 32'd0;
        dc_ep[k] = 32'd0;
      end
      epoch <= 32'd1;
      ic_pending <= 1'b0;
      dc_pending <= 1'b0;
    end else if (lwe) begin
      epoch <= (epoch == 32'd0) ? 32'd1 : (epoch + 32'd1);
      ic_pending <= 1'b0;
      dc_pending <= 1'b0;
    end else if (!halt) begin
      if (ic_ready_now) begin
        if (!ic_hit) begin
          for (int b = 0; b < LINE_BYTES; b++)
            ic_data[i_idx*LINE_BYTES+b] =
              ram[((pc_if & 32'hFFFFFFF0) + b) & BACK_MASK];
          ic_ep[i_idx] = epoch;
          ic_tag[i_idx] = i_tag;
        end
        ic_pending <= 1'b0;
      end else if (!ic_pending && LAT > 1) begin
        ic_pending <= 1'b1;
        ic_count   <= 1;
        ic_ptag    <= i_tag;
      end else if (ic_pending && (ic_ptag == i_tag) && !ic_hit) begin
        ic_count <= ic_count + 1;
      end else begin
        ic_pending <= 1'b0;
      end

      if (dreq) begin
        if (dc_ready_now) begin
          if (!(uart_store || uart_load)) begin
            if (!dc_hit) begin
              for (int b = 0; b < LINE_BYTES; b++)
                dc_data[d_idx*LINE_BYTES+b] =
                  ram[((ea & 32'hFFFFFFF0) + b) & BACK_MASK];
              dc_ep[d_idx] = epoch;
              dc_tag[d_idx] = d_tag;
            end
            if (idex_st) begin
              sb = ea & BACK_MASK;
              ram[sb] = sd_raw[7:0];
              if (d_off < LINE_BYTES)
                dc_data[d_idx*LINE_BYTES+d_off] = sd_raw[7:0];
              if (ssz == 2'b01 || ssz == 2'b10) begin
                ram[(sb + 1) & BACK_MASK] = sd_raw[15:8];
                if ((d_off + 1) < LINE_BYTES)
                  dc_data[d_idx*LINE_BYTES+d_off+1] = sd_raw[15:8];
              end
              if (ssz == 2'b10) begin
                ram[(sb + 2) & BACK_MASK] = sd_raw[23:16];
                ram[(sb + 3) & BACK_MASK] = sd_raw[31:24];
                if ((d_off + 2) < LINE_BYTES)
                  dc_data[d_idx*LINE_BYTES+d_off+2] = sd_raw[23:16];
                if ((d_off + 3) < LINE_BYTES)
                  dc_data[d_idx*LINE_BYTES+d_off+3] = sd_raw[31:24];
              end
              ic_ep[(ea >> LINE_SHIFT) & IC_MASK] = 32'd0;
              if (d_off > 12) begin
                ic_ep[((ea >> LINE_SHIFT) + 1) & IC_MASK] = 32'd0;
                dc_ep[(d_idx + 1) & DC_MASK] = 32'd0;
              end
            end else begin
              if (dc_hit && (d_off <= 12)) begin
                dc_ep[d_idx] = epoch;
                dc_tag[d_idx] = d_tag;
              end
            end
          end
          dc_pending <= 1'b0;
        end else if (!dc_pending && LAT > 1) begin
          dc_pending <= 1'b1;
          dc_count   <= 1;
          dc_ptag    <= d_tag;
        end else if (dc_pending && (dc_ptag == d_tag) && !dc_hit) begin
          dc_count <= dc_count + 1;
        end else begin
          dc_pending <= 1'b0;
        end
      end else begin
        dc_pending <= 1'b0;
      end
    end
  end
  /* verilator lint_on UNUSED */
  /* verilator lint_on BLKSEQ */
  /* verilator lint_on WIDTHEXPAND */
  /* verilator lint_on WIDTHTRUNC */
endmodule
`default_nettype wire
