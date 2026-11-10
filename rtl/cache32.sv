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
`ifndef FPGA
  // Atomics (LR/SC/AMO*.w): processed with the load; the op(old,src) store is
  // performed at the load-completion cycle inside this device (sim CPU only;
  // reservation tracked here: LR sets, SC consumes, matching store clears).
  input  logic        amo_v, amo_lr, amo_sc,
  input  logic [4:0]  amo5,
  input  logic [31:0] amo_new,
  output logic        amo_sc_ok,
`endif
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
  output logic        mem_ready,
  output logic        clint_commit,
  input  logic [31:0] clint_ld_in
`ifdef LINUX
 ,input  logic        uart_rx_ready,
  input  logic [7:0]  uart_rx_in,
  output logic        uart_tx_valid,
  output logic [7:0]  uart_tx_out,
  output logic        uart_rx_pending,
  output logic        uart_tx_ready
`endif
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
`ifdef LINUX
  localparam int BACK_WORDS = 16 * 1024 * 1024;  // 64 MB for the Linux runner
  localparam int IC_LINES   = 1024;
  localparam int DC_LINES   = 1024;
`else
  localparam int BACK_WORDS = 65536;
  localparam int IC_LINES   = 1024;
  localparam int DC_LINES   = 1024;
`endif
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

  // L4 Linux platform: RAM is exactly 64 MB at 0x8000_0000 plus a 2 MB LOW
  // window at 0x0 (pinned spike puts its boot stub + --dtb blob at 0x1000/0x1020
  // and OpenSBI scans RAM from a1=0x1020, so low RAM must be real RAM, not
  // aliased into the kernel window). CLINT/PLIC/UART pages keep their MMIO
  // paths; other unmapped addresses still read 0 / drop stores.
`ifdef LINUX
  localparam int LOW_WORDS = 512 * 1024;   // 2 MB low RAM
  localparam int LOW_BYTES = LOW_WORDS * 4;
  localparam int LOW_MASK  = LOW_BYTES - 1;
  logic ram_ok, ic_ram_ok, low_ok, ic_low_ok;
  assign ram_ok    = ((ea >> 26) == 6'h20);
  assign ic_ram_ok = (pc_if[31:26] == 6'h20);
  assign low_ok    = (ea[31:21] == 11'd0);
  assign ic_low_ok = (pc_if[31:21] == 11'd0);
`else
  localparam bit ram_ok = 1;
  localparam bit ic_ram_ok = 1;
  localparam bit low_ok = 1;
  localparam bit ic_low_ok = 1;
`endif

  // P2 speed: backing + cache lines are WORD arrays (VlUnpacked<uint32_t>):
  // 1-2 word ops instead of 4-16 byte ops per access; byte semantics kept via
  // rbwb/rb_ic/rb_dc word merge + lane-masked RMW stores. Byte order little
  // endian within the word (byte b == rw[b>>2] lane (b&3)*8).
  (* BRAM = 1 *) logic [31:0] rw  [0:BACK_WORDS-1];
`ifdef LINUX
  (* BRAM = 1 *) logic [31:0] lrw [0:LOW_WORDS-1];   // LOW RAM backing (boot stub+DTB)
`endif
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
`ifndef FPGA
  logic res_v = 1'b0;
  logic [31:0] res_a = 32'h0;
  logic amo_done_now, amo_sc_done, amo_ok_now;
`endif
  int i_idx, i_tag, i_mbase;
  int d_idx, d_tag, d_off, d_cache_base, sb;
  int w0, sft, msk, nby;
  int i_s, i_t;
  logic ic_hit, dc_hit, ic_p_ready, dc_p_ready, dreq, uart_store, uart_load;
  logic dc_ready_now, ic_ready_now, dc_cross_ready;
  logic clint_match, clint_store, clint_load;
  logic [31:0] ld_norm;
`ifdef DOOM_BIG
  logic key_load, key_store;
`endif
`ifdef LINUX
  logic plic_match, plic_store, plic_load;
  logic uart_load_data, uart_store_data, uart_status_load;
  logic [7:0] uart_byte = 8'h0;
  logic uart_pend = 1'b0;
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
`ifdef LINUX
    if (addr[31:21] == 11'd0) begin
      w = (addr >> 2) & (LOW_WORDS - 1);
      s = (addr & 3) * 8;
      rbwb = (s == 0) ? lrw[w] :
             ((lrw[w] >> s) | (lrw[(w + 1) & (LOW_WORDS - 1)] << (32 - s)));
    end else if (addr[31:26] == 6'h20) begin
      w = (addr >> 2) & (BACK_WORDS - 1);
      s = (addr & 3) * 8;
      rbwb = (s == 0) ? rw[w] :
             ((rw[w] >> s) | (rw[(w + 1) & (BACK_WORDS - 1)] << (32 - s)));
    end else rbwb = 32'h0;
`else
    w = (addr >> 2) & (BACK_WORDS - 1);
    s = (addr & 3) * 8;
    rbwb = (s == 0) ? rw[w] : ((rw[w] >> s) | (rw[(w + 1) & (BACK_WORDS - 1)] << (32 - s)));
`endif
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
`ifdef LINUX
    uart_store = dreq && idex_st && ((ea & 32'hFFFFF000) == 32'h1000_0000);
    uart_load  = dreq && idex_ld && ((ea & 32'hFFFFF000) == 32'h1000_0000);
`else
    uart_store = dreq && idex_st && (ea == UART_ADDR);
    uart_load  = dreq && idex_ld && (ea == UART_ADDR);
`endif
    clint_match = dreq && ((ea & 32'hFFFF_0000) == 32'h0200_0000);
    clint_store = clint_match && idex_st;
    clint_load  = clint_match && idex_ld;
`ifdef LINUX
    plic_match  = dreq && ((ea & 32'hFFFFF000) == 32'h0C00_0000);
    plic_store  = plic_match && idex_st;
    plic_load   = plic_match && idex_ld;
`endif
`ifdef DOOM_BIG
    key_load   = dreq && idex_ld && (ea == KEY_ADDR);
    key_store  = dreq && idex_st && (ea == KEY_ADDR);
`endif
    dc_cross_ready = dreq && (d_off > 12);
`ifdef LINUX
    uart_load_data   = uart_load && ((ea & 32'hFFF) == 32'h000);
    uart_status_load = uart_load && ((ea & 32'hFFF) == 32'h005);
    uart_store_data  = uart_store && ((ea & 32'hFFF) == 32'h000);
`endif

    ic_p_ready = ic_pending && (ic_ptag == i_tag) && (ic_count >= READY_AT);
    dc_p_ready = dc_pending && (dc_ptag == d_tag) && (dc_count >= READY_AT);

    ic_ready_now = ic_hit || ic_p_ready || (LAT == 1);
    dc_ready_now = dc_hit || dc_p_ready || dc_cross_ready ||
                   uart_store || uart_load || clint_match ||
`ifdef LINUX
                   plic_store || plic_load ||
`endif
`ifdef DOOM_BIG
                   key_load || key_store ||
`endif
                   (LAT == 1);
`ifndef FPGA
    amo_done_now = dreq && amo_v && dc_ready_now && !clint_match;
    amo_sc_done  = amo_done_now && amo_sc;
    amo_ok_now   = amo_sc_done && res_v && (res_a == ea);
    amo_sc_ok    = amo_ok_now;
`endif

    fetch_ready = (reset || halt) ? 1'b1 : ic_ready_now;
    fetch_insn  = ic_ready_now ? (ic_hit ? rb_ic(pc_if) : rbwb(pc_if)) : 32'h0;
    mem_ready   = (reset || halt) ? 1'b1 : (!dreq || dc_ready_now);
    ld_norm = ((dc_hit && (d_off <= 12)) ? rb_dc(ea) : rbwb(ea));
`ifdef LINUX
    if (uart_load) begin
      if (uart_status_load) ld_norm = (32'h60 | (uart_pend ? 32'h1 : 32'h0));
      else if (uart_load_data) ld_norm = (uart_pend ? {24'h0,uart_byte} :
                                          (uart_rx_ready ? {24'h0,uart_rx_in} : 32'h0));
      else ld_norm = 32'h0;
    end else if (plic_load) ld_norm = 32'h0;
`endif
`ifdef DOOM_BIG
    if (key_load) ld_norm = key_in;
`endif
`ifdef FPGA
    ld_raw = dc_ready_now ? (clint_load ? clint_ld_in : ld_norm) : 32'h0;
`else
    ld_raw = dc_ready_now ? (clint_load ? clint_ld_in :
                   amo_sc_done ? (amo_ok_now ? 32'h0 : 32'h1) : ld_norm) : 32'h0;
`endif
    clint_commit = clint_store && dc_ready_now;  end
`ifdef SCDBG2
  always_comb
    if (idex_valid && (idex_ld || idex_st) && !reset && !halt)
      $display("CACC ea=%08x ld=%b st=%b ready=%b norm=%08x raw=%08x hit=%b rbwb=%08x idx=%x tag=%x ep=%0d epoch=%0d dt=%08x",
               ea, idex_ld, idex_st, dc_ready_now, ld_norm, ld_raw, dc_hit, rbwb(ea), d_idx, d_tag,
               dc_ep[d_idx], epoch, dc_tag[d_idx]);
`endif
`ifdef DOOM_BIG
  assign key_hit = key_load && dc_ready_now;
`endif
`ifdef LINUX
  assign uart_tx_valid = uart_store_data && dc_ready_now;
  assign uart_tx_out = sd_raw[7:0];
  assign uart_tx_ready = 1'b1;
  assign uart_rx_pending = uart_pend;
`endif

`ifdef SCDBG3
  logic [63:0] dbg_cyc3 = 0;
  always_ff @(posedge clk) if (!reset) dbg_cyc3 <= dbg_cyc3 + 64'd1;
  always_ff @(posedge clk) begin
    if (!reset) begin
      if (dbg_cyc3 >= 64'd211665398 && dbg_cyc3 < 64'd211665412)
        $display("SCDBG9 IN c=%0d v=%b st=%b ld=%b ea=%08x sd=%08x aamo=%b pf=%08x", dbg_cyc3+64'd0, idex_valid, idex_st, idex_ld, ea, sd_raw, amo_v, pc_if);
    end
  end
`endif
  always_ff @(posedge clk) begin
    if (lwe) begin
`ifdef LINUX
      if (lwa[31:21] == 11'd0) begin
        sb = lwa & LOW_MASK;
        w0 = sb >> 2; sft = (lwa & 3) * 8;
        if (sft == 0) lrw[w0] = lwd;
        else begin
          lrw[w0] = (lrw[w0] & ~(32'hFFFF_FFFF << sft)) | (lwd << sft);
          lrw[(w0 + 1) & (LOW_WORDS - 1)] =
            (lrw[(w0 + 1) & (LOW_WORDS - 1)]
             & ~(32'hFFFF_FFFF >> (32 - sft))) | (lwd >> (32 - sft));
        end
      end else
`endif
      begin
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
`ifdef LINUX
      if (uart_load_data && dc_ready_now) uart_pend <= 1'b0;
      else if (uart_rx_ready && !uart_pend) begin
        uart_pend <= 1'b1;
        uart_byte <= uart_rx_in;
      end
`endif
      if (ic_ready_now) begin
        if (!ic_hit) begin
          for (int w = 0; w < LINE_BYTES/4; w++)
            icw[i_idx*4+w] =
`ifdef LINUX
              ic_ram_ok ? rw[((((pc_if & 32'hFFFFFFF0) >> 2) + w)) & (BACK_WORDS - 1)]
                        : (ic_low_ok ? lrw[((((pc_if & 32'hFFFFFFF0) >> 2) + w))
                                     & (LOW_WORDS - 1)] : 32'h0);
`else
              rw[((((pc_if & 32'hFFFFFFF0) >> 2) + w)) & (BACK_WORDS - 1)];
`endif
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
`ifdef SCDBG3
          if (dbg_cyc3 >= 64'd211665400 && dbg_cyc3 < 64'd211665410)
            $display("SCDBG8 MEMOP c=%0d vld=%b st=%b ld=%b ea=%08x ssz=%b sd=%08x hit=%0d off=%0d tag=%08x have=%08x", dbg_cyc3, idex_valid, idex_st, idex_ld, ea, ssz, sd_raw, dc_hit, d_off, d_tag, dc_tag[d_idx]);
`endif
          if (!(uart_store || uart_load || clint_store
`ifdef DOOM_BIG
               || key_store
`endif
`ifdef LINUX
               || plic_store || plic_load
`endif
              )) begin
`ifdef SCDBG3
            if (idex_ld && (ea[31:12] == 20'h82850))
              $display("SCDBG3 LD c=%0d ea=%08x hit=%0d off=%0d want=%08x have=%08x cep=%08x epoch=%08x word=%08x", dbg_cyc3, ea, dc_hit, d_off, d_tag, dc_tag[d_idx], dc_ep[d_idx], epoch, rb_dc(ea));
            if ((idex_st || idex_ld) && (ea[31:12] == 20'h82850))
              $display("SCDBG6 ACC c=%0d ea=%08x st=%b ld=%b vld=%b dreq=%b ready=%b hit=%b rok=%b lok=%b ssz=%b sd=%08x", dbg_cyc3, ea, idex_st, idex_ld, idex_valid, dreq, dc_ready_now, dc_hit, ram_ok, low_ok, ssz, sd_raw);
`endif
            if (!dc_hit) begin
              for (int w = 0; w < LINE_BYTES/4; w++)
                dcw[d_idx*4+w] =
`ifdef LINUX
                  ram_ok ? rw[((((ea & 32'hFFFFFFF0) >> 2)) + w) & (BACK_WORDS - 1)]
                         : (low_ok ? lrw[((((ea & 32'hFFFFFFF0) >> 2)) + w)
                                    & (LOW_WORDS - 1)] : 32'h0);
`else
                  rw[((((ea & 32'hFFFFFFF0) >> 2)) + w) & (BACK_WORDS - 1)];
`endif
              dc_ep[d_idx] = epoch;
              dc_tag[d_idx] = d_tag;
            end
            if (idex_st && (ram_ok || low_ok)) begin
`ifdef SCDBG3
              if (ea[31:12] == 20'h82850)
                $display("SCDBG3 ST c=%0d ea=%08x sd=%08x hit=%0d off=%0d", dbg_cyc3, ea, sd_raw, dc_hit, d_off);
`endif
              w0  = (ea >> 2) & (BACK_WORDS - 1);
              sft = (ea & 3) * 8;
              nby = (ssz == 2'b00) ? 1 : (ssz == 2'b01) ? 2 : 4;
              msk = (nby == 4) ? 32'hFFFF_FFFF
                               : ((32'h1 << (nby * 8)) - 32'h1);
`ifdef LINUX
              if (low_ok) begin
                w0 = w0 & (LOW_WORDS - 1);
                lrw[w0] = (lrw[w0] & ~(msk << sft)) | (sd_raw << sft);
                if ((ea & 3) + nby > 4)
                  lrw[(w0 + 1) & (LOW_WORDS - 1)] =
                    (lrw[(w0 + 1) & (LOW_WORDS - 1)] & ~(msk >> (32 - sft))) |
                    (sd_raw >> (32 - sft));
              end else
`endif
              begin
              rw[w0] = (rw[w0] & ~(msk << sft)) | (sd_raw << sft);
              if ((ea & 3) + nby > 4)
                rw[(w0 + 1) & (BACK_WORDS - 1)] =
                  (rw[(w0 + 1) & (BACK_WORDS - 1)] & ~(msk >> (32 - sft))) |
                  (sd_raw >> (32 - sft));
              end
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
`ifndef FPGA
            if (idex_st) begin
              if (ea == res_a && (ram_ok || low_ok)) res_v <= 1'b0;
            end
            if (amo_done_now && (ram_ok || low_ok)) begin
`ifdef SCDBG
              $display("DBG AMO ea=%08x v=%0d lr=%0d sc=%0d ok=%0d", ea, amo_v, amo_lr, amo_sc, amo_ok_now);
`endif
              if (amo_lr) begin
                res_v <= 1'b1; res_a <= ea;
              end else if (amo_sc) begin
`ifdef SCDBG
                $display("DBG SC ea=%08x res_v=%0d res_a=%08x ok=%0d", ea, res_v, res_a, amo_ok_now);
`endif
                res_v <= 1'b0;  // SC loses the reservation either way
                if (amo_ok_now) begin
                  w0 = (ea >> 2) & (BACK_WORDS - 1);
`ifdef LINUX
                  if (low_ok) lrw[w0 & (LOW_WORDS - 1)] <= amo_new;
                  else
`endif
                  rw[w0] <= amo_new;
                  if (d_off <= 12) dcw[d_idx*4+(d_off>>2)] <= amo_new;
                  i_s = (ea >> LINE_SHIFT) & IC_MASK;
                  i_t = ea >> (LOGIC + LINE_SHIFT);
                  if (ic_ep[i_s] == epoch && ic_tag[i_s] == i_t) ic_ep[i_s] = 32'd0;
                end
              end else begin
                if (res_a == ea) res_v <= 1'b0;
                w0 = (ea >> 2) & (BACK_WORDS - 1);
`ifdef LINUX
                if (low_ok) lrw[w0 & (LOW_WORDS - 1)] <= amo_new;
                else
`endif
                rw[w0] <= amo_new;
                if (d_off <= 12) dcw[d_idx*4+(d_off>>2)] <= amo_new;
                i_s = (ea >> LINE_SHIFT) & IC_MASK;
                i_t = ea >> (LOGIC + LINE_SHIFT);
                if (ic_ep[i_s] == epoch && ic_tag[i_s] == i_t) ic_ep[i_s] = 32'd0;
              end
            end
`endif
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
