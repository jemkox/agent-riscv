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
`ifdef DOOM_BIG
  input  logic        dbg_re,
  input  logic [31:0] dbg_ra,
  output logic [31:0] dbg_rd,
`endif
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
`ifdef DOOM_BIG
  // M10f keyboard FIFO feed for DG_GetKey (C++ testbench writes it each
  // cycle; key_hit pulses when a load at KEY_ADDR consumed the head).
  input  logic [31:0] key_in,
  output logic        key_hit,
  // P3 counters: I/D cache misses (pending-fill initiations)
  output logic [31:0] stat_icm = 0,
  output logic [31:0] stat_dcm = 0,
`endif
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
  localparam int IC_LINES   = 1024;   // 16 KB I-cache (P1)
  localparam int DC_LINES   = 1024;   // 16 KB D-cache (P1)
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

  // P2 speed: backing + cache lines are WORD arrays (VlUnpacked<uint32_t>):
  // 1-2 word ops instead of 4-16 byte ops per access; byte semantics kept via
  // rbwb/rb_ic/rb_dc word merge + lane-masked RMW stores. Byte order little
  // endian within the word (byte b == rw[b>>2] lane (b&3)*8).
  (* BRAM = 1 *) logic [31:0] rw  [0:BACK_WORDS-1];
  (* BRAM = 1 *) logic [31:0] icw [0:IC_LINES*4-1];
  (* BRAM = 1 *) logic [31:0] dcw [0:DC_LINES*4-1];
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
  int w0, sft, msk, nby;
  int i_s, i_t;
  logic ic_hit, dc_hit, ic_p_ready, dc_p_ready, dreq, uart_store, uart_load;
  logic dc_ready_now, ic_ready_now, dc_cross_ready;
`ifdef DOOM_BIG
  logic key_load, key_store;
`endif
`ifdef DOOM_BIG
  localparam logic [31:0] UART_ADDR = 32'h1FF0_0000; /* above the WAD blob */
  localparam logic [31:0] KEY_ADDR  = 32'h1FF0_0008; /* M10f key-FIFO load */
`else
  localparam logic [31:0] UART_ADDR = 32'h1000_0000;
`endif

  function [31:0] rbwb;
    input int addr;
    int w, s;
    w = (addr >> 2) & (BACK_WORDS - 1);
    s = (addr & 3) * 8;
    rbwb = (s == 0) ? rw[w] : ((rw[w] >> s) | (rw[(w + 1) & (BACK_WORDS - 1)] << (32 - s)));
  endfunction

  function [31:0] rb_ic;
    input [31:0] addr;
    int base, off;
    base = ((addr >> LINE_SHIFT) & IC_MASK) * 4;
    off  = addr & (LINE_BYTES - 1);
    if ((off & 3) == 0) rb_ic = icw[base + (off >> 2)];
    else rb_ic = (icw[base + (off >> 2)] >> ((off & 3) * 8)) |
                 (icw[base + (off >> 2) + 1] << (32 - ((off & 3) * 8)));
  endfunction

  function [31:0] rb_dc;
    input [31:0] addr;
    int base, off;
    base = ((addr >> LINE_SHIFT) & DC_MASK) * 4;
    off  = addr & (LINE_BYTES - 1);
    if ((off & 3) == 0) rb_dc = dcw[base + (off >> 2)];
    else rb_dc = (dcw[base + (off >> 2)] >> ((off & 3) * 8)) |
                 (dcw[base + (off >> 2) + 1] << (32 - ((off & 3) * 8)));
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
`ifdef DOOM_BIG
    key_load   = dreq && idex_ld && (ea == KEY_ADDR);
    key_store  = dreq && idex_st && (ea == KEY_ADDR);
`endif
    dc_cross_ready = dreq && (d_off > 12);

    ic_p_ready = ic_pending && (ic_ptag == i_tag) && (ic_count >= READY_AT);
    dc_p_ready = dc_pending && (dc_ptag == d_tag) && (dc_count >= READY_AT);

    ic_ready_now = ic_hit || ic_p_ready || (LAT == 1);
    dc_ready_now = dc_hit || dc_p_ready || dc_cross_ready ||
                   uart_store || uart_load ||
`ifdef DOOM_BIG
                   key_load || key_store ||
`endif
                   (LAT == 1);

    fetch_ready = (reset || halt) ? 1'b1 : ic_ready_now;
    fetch_insn  = ic_ready_now ? (ic_hit ? rb_ic(pc_if) : rbwb(pc_if)) : 32'h0;
    mem_ready   = (reset || halt) ? 1'b1 : (!dreq || dc_ready_now);
    ld_raw = dc_ready_now ?
             (uart_load ? 32'h0 :
`ifdef DOOM_BIG
              (key_load ? key_in :
`endif
               ((dc_hit && (d_off <= 12)) ? rb_dc(ea) : rbwb(ea))
`ifdef DOOM_BIG
              )
`endif
             ) :
             32'h0;
  end
`ifdef DOOM_BIG
  assign key_hit = key_load && dc_ready_now;
`endif

  always_ff @(posedge clk) begin
    if (lwe) begin
      sb = lwa & BACK_MASK;
      w0 = sb >> 2; sft = (lwa & 3) * 8;
      if (sft == 0) rw[w0] = lwd;
      else begin
        rw[w0] = (rw[w0] & ~(32'hFFFF_FFFF << sft)) | (lwd << sft);
        rw[(w0 + 1) & (BACK_WORDS - 1)] =
          (rw[(w0 + 1) & (BACK_WORDS - 1)]
           & ~(32'hFFFF_FFFF >> (32 - sft))) | (lwd >> (32 - sft));
      end
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
          for (int w = 0; w < LINE_BYTES/4; w++)
            icw[i_idx*4+w] =
              rw[((((pc_if & 32'hFFFFFFF0) >> 2) + w)) & (BACK_WORDS - 1)];
          ic_ep[i_idx] = epoch;
          ic_tag[i_idx] = i_tag;
        end
        ic_pending <= 1'b0;
      end else if (!ic_pending && LAT > 1) begin
        ic_pending <= 1'b1;
        ic_count   <= 1;
        ic_ptag    <= i_tag;
`ifdef DOOM_BIG
        stat_icm   <= stat_icm + 32'd1;
`endif
      end else if (ic_pending && (ic_ptag == i_tag) && !ic_hit) begin
        ic_count <= ic_count + 1;
      end else begin
        ic_pending <= 1'b0;
      end

      if (dreq) begin
        if (dc_ready_now) begin
          if (!(uart_store || uart_load
`ifdef DOOM_BIG
               || key_store
`endif
              )) begin
            if (!dc_hit) begin
              for (int w = 0; w < LINE_BYTES/4; w++)
                dcw[d_idx*4+w] =
                  rw[((((ea & 32'hFFFFFFF0) >> 2)) + w) & (BACK_WORDS - 1)];
              dc_ep[d_idx] = epoch;
              dc_tag[d_idx] = d_tag;
            end
            if (idex_st) begin
              w0  = (ea >> 2) & (BACK_WORDS - 1);
              sft = (ea & 3) * 8;
              nby = (ssz == 2'b00) ? 1 : (ssz == 2'b01) ? 2 : 4;
              msk = (nby == 4) ? 32'hFFFF_FFFF
                               : ((32'h1 << (nby * 8)) - 32'h1);
              rw[w0] = (rw[w0] & ~(msk << sft)) | (sd_raw << sft);
              if ((ea & 3) + nby > 4)
                rw[(w0 + 1) & (BACK_WORDS - 1)] =
                  (rw[(w0 + 1) & (BACK_WORDS - 1)] & ~(msk >> (32 - sft))) |
                  (sd_raw >> (32 - sft));
              if (d_off <= 12) begin
                dcw[d_idx*4+(d_off>>2)] =
                  (dcw[d_idx*4+(d_off>>2)] & ~(msk << sft)) | (sd_raw << sft);
                if ((d_off & 3) + nby > 4)
                  dcw[d_idx*4+(d_off>>2)+1] =
                    (dcw[d_idx*4+(d_off>>2)+1] & ~(msk >> (32 - sft))) |
                    (sd_raw >> (32 - sft));
              end
              i_s = (ea >> LINE_SHIFT) & IC_MASK;
              i_t = ea >> (LOGIC + LINE_SHIFT);
              if (ic_ep[i_s] == epoch && ic_tag[i_s] == i_t)
                ic_ep[i_s] = 32'd0;
              if (d_off > 12) begin
                if (ic_ep[(i_s + 1) & IC_MASK] == epoch &&
                    (ic_tag[(i_s + 1) & IC_MASK] == i_t ||
                     ic_tag[(i_s + 1) & IC_MASK] == (i_t + 32'h1)))
                  ic_ep[(i_s + 1) & IC_MASK] = 32'd0;
                dc_ep[d_idx] = 32'd0;
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
`ifdef DOOM_BIG
          stat_dcm   <= stat_dcm + 32'd1;
`endif
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
`ifdef DOOM_BIG
  // Debug word readback straight from backing RAM (only when dbg_re set; C++
  // P2 runner now reads rootp->ram directly, so this runs at most once per
  // loader/capture call, not every eval).
  assign dbg_rd = dbg_re ? rbwb(dbg_ra) : 32'h0;
`endif
endmodule
`default_nettype wire
