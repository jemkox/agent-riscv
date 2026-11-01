// Configurable-latency cache model over a coherent backing RAM.
// Caches only model hit/miss/pending latency; ready reads use backing RAM.
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
`ifdef SMALL_CACHE
  localparam int BACK_WORDS = 16;
  localparam int IC_LINES   = 4;
  localparam int DC_LINES   = 4;
`else
  localparam int BACK_WORDS = 65536;
  localparam int IC_LINES   = 1024;
  localparam int DC_LINES   = 1024;
`endif
  localparam int BACK_BYTES = BACK_WORDS * 4;
  localparam int BACK_MASK  = BACK_BYTES - 1;
  localparam int IC_MASK    = IC_LINES - 1;
  localparam int DC_MASK    = DC_LINES - 1;
  localparam int LOGIC      = $clog2(IC_LINES);
  localparam int LOGDC      = $clog2(DC_LINES);
  localparam int READY_AT   = (LAT > 1) ? (LAT - 1) : 0;

  logic [7:0] ram [0:BACK_BYTES-1];
  logic [31:0] ic_tag [0:IC_LINES-1];
  logic [31:0] dc_tag [0:DC_LINES-1];
  logic        ic_valid [0:IC_LINES-1];
  logic        dc_valid [0:DC_LINES-1];
  logic        ic_pending = 1'b0;
  logic        dc_pending = 1'b0;
  logic [31:0] ic_ptag = 32'h0;
  logic [31:0] dc_ptag = 32'h0;
  int ic_count = 0;
  int dc_count = 0;
  int i_w, i_tag, i_idx;
  int d_w, d_tag, d_idx, sb;
  logic ic_hit, dc_hit, ic_p_ready, dc_p_ready, dreq, uart_store, uart_load;
  logic ic_ready_now, dc_ready_now;
  localparam logic [31:0] UART_ADDR = 32'h1000_0000;

  function [31:0] rbwb;
    input int addr;
    int b;
    b = addr & BACK_MASK;
    rbwb = { ram[(b + 3) & BACK_MASK], ram[(b + 2) & BACK_MASK],
             ram[(b + 1) & BACK_MASK], ram[b & BACK_MASK] };
  endfunction

  always_comb begin
    i_w    = {2'b0, pc_if[31:2]};
    i_tag  = i_w >> (LOGIC + 2);
    i_idx  = (i_w >> 2) & IC_MASK;
    d_w    = {2'b0, ea[31:2]};
    d_tag  = d_w >> (LOGDC + 2);
    d_idx  = (d_w >> 2) & DC_MASK;

    ic_hit = ic_valid[i_idx] && (ic_tag[i_idx] == i_tag);
    dc_hit = dc_valid[d_idx] && (dc_tag[d_idx] == d_tag);
    dreq = idex_valid && (idex_ld || idex_st) && !reset && !halt && !lwe;
    uart_store = dreq && idex_st && (ea == UART_ADDR);
    uart_load  = dreq && idex_ld && (ea == UART_ADDR);

    ic_p_ready = ic_pending && (ic_ptag == i_tag) && (ic_count >= READY_AT);
    dc_p_ready = dc_pending && (dc_ptag == d_tag) && (dc_count >= READY_AT);

    ic_ready_now = ic_hit || ic_p_ready || (LAT == 1);
    dc_ready_now = dc_hit || dc_p_ready || uart_store || uart_load || (LAT == 1);

    fetch_ready = (reset || halt) ? 1'b1 : ic_ready_now;
    fetch_insn  = ic_ready_now ? rbwb(pc_if) : 32'h0;
    mem_ready   = (reset || halt) ? 1'b1 : (!dreq || dc_ready_now);
    ld_raw      = dc_ready_now ? (uart_load ? 32'h0 : rbwb(ea)) : 32'h0;
  end

  always_ff @(posedge clk) begin
    if (lwe) begin
      sb = lwa & BACK_MASK;
      ram[sb]           = lwd[7:0];
      ram[(sb + 1) & BACK_MASK] = lwd[15:8];
      ram[(sb + 2) & BACK_MASK] = lwd[23:16];
      ram[(sb + 3) & BACK_MASK] = lwd[31:24];
    end

    if (reset) begin
      for (int k = 0; k < IC_LINES; k++) ic_valid[k] = 1'b0;
      for (int k = 0; k < DC_LINES; k++) dc_valid[k] = 1'b0;
      ic_pending <= 1'b0;
      dc_pending <= 1'b0;
    end else if (lwe) begin
      for (int k = 0; k < IC_LINES; k++) ic_valid[k] = 1'b0;
      for (int k = 0; k < DC_LINES; k++) dc_valid[k] = 1'b0;
      ic_pending <= 1'b0;
      dc_pending <= 1'b0;
    end else if (!halt) begin
      if (ic_ready_now) begin
        if (!ic_hit) begin
          ic_valid[i_idx] = 1'b1;
          ic_tag[i_idx]   = i_tag;
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
          if (!uart_store && !uart_load) begin
            dc_valid[d_idx] = 1'b1;
            dc_tag[d_idx]   = d_tag;
            if (idex_st) begin
              sb = ea & BACK_MASK;
              ram[sb]           = sd_raw[7:0];
              if (ssz == 2'b01 || ssz == 2'b10)
                ram[(sb + 1) & BACK_MASK] = sd_raw[15:8];
              if (ssz == 2'b10) begin
                ram[(sb + 2) & BACK_MASK] = sd_raw[23:16];
                ram[(sb + 3) & BACK_MASK] = sd_raw[31:24];
              end
              ic_valid[d_idx] = 1'b0;
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
