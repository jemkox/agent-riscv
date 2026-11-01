// MDU for the FPGA build: 16x16 partial-product multiply on iCE40 DSP blocks
// (`synth_ice40 -dsp` maps the 17x17* products + accumulate adds to SB_MAC16).
// MUL path: 4 partials in 4 accumulate cycles (64-bit acc), ~4-cycle latency.
// DIV/REM: unchanged 33-step restoring divider.  The SIM build uses rtl/mdiu_fast.sv.
/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off DECLFILENAME */
module mdiu_fpga (
  input  logic        clk,
  input  logic        reset,
  input  logic        idex_valid,
  input  logic        is_m,
  input  logic        is_ill,
  input  logic        idex_done,
  input  logic        ex_stall,
  input  logic [2:0]  op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic        md_active,
  output logic        md_done_now,
  output logic [31:0] result
);
  logic active = 1'b0;
  logic mulmode = 1'b0;      // 1 = multiply accumulate, 0 = divide loop
  logic [2:0] cur_op = 3'd0;
  logic [16:0] aHe = 17'h0, aLe = 17'h0, bHe = 17'h0, bLe = 17'h0;
  logic [63:0] acc = 64'h0;
  logic [31:0] Dm = 32'h0;   // dividend magnitude, shifted left
  logic [31:0] Bm = 32'h0;   // divisor magnitude
  logic [31:0] Rem = 32'h0;
  logic [31:0] Q = 32'h0;
  logic [2:0] mstep = 3'd0;  // partial index 0..3
  logic [5:0] step = 6'd0;   // divide step
  logic div_signed = 1'b0;
  logic neg_q = 1'b0;
  logic neg_r = 1'b0;

  wire [15:0] aL = a[15:0];
  wire [15:0] aH = a[31:16];
  wire [15:0] bL = b[15:0];
  wire [15:0] bH = b[31:16];
  // per-op half signedness: MULH: both signed; MULHSU: a high signed; MULHU: none.
  wire ah_neg = (op == 3'd1 || op == 3'd2);
  wire bh_neg = (op == 3'd1);

  logic n_active;
  logic n_mulmode;
  logic [2:0] n_cur_op;
  logic [16:0] n_aHe, n_aLe, n_bHe, n_bLe;
  logic [63:0] n_acc;
  logic [31:0] n_Dm, n_Bm, n_Rem, n_Q;
  logic [2:0] n_mstep;
  logic [5:0] n_step;
  logic n_div_signed, n_neg_q, n_neg_r;
  logic n_done;
  logic [31:0] n_result;
  logic [32:0] nr;
  logic [32:0] ssub;

  // partials computed each cycle from the stored halves (17x17 signed/unsigned mix)
  wire [33:0] p_hl = $signed(aHe) * $signed(bLe);
  wire [33:0] p_lh = $signed(aLe) * $signed(bHe);
  wire [33:0] p_hh = $signed(aHe) * $signed(bHe);
  wire [33:0] p_il = $signed({1'b0, aL}) * $signed({1'b0, bL});
  // 16-bit lane accumulate (short carries, like the DSP's own P accumulator)
  wire [16:0] hl1 = acc[31:16] + {1'b0, p_hl[15:0]};
  wire [16:0] hl2 = acc[47:32] + {1'b0, p_hl[31:16]} + {16'b0, hl1[16]};
  wire [16:0] hl3 = acc[63:48] + {15'b0, hl2[16]} + {{14{p_hl[33]}}, p_hl[33:32]};
  wire [16:0] lh1 = acc[31:16] + {1'b0, p_lh[15:0]};
  wire [16:0] lh2 = acc[47:32] + {1'b0, p_lh[31:16]} + {16'b0, lh1[16]};
  wire [16:0] lh3 = acc[63:48] + {15'b0, lh2[16]} + {{14{p_lh[33]}}, p_lh[33:32]};
  wire [16:0] hh1 = acc[47:32] + {1'b0, p_hh[15:0]};
  wire [16:0] hh2 = acc[63:48] + {1'b0, p_hh[31:16]} + {15'b0, hh1[16]};

  always_comb begin
    n_active = active;
    n_mulmode = mulmode;
    n_cur_op = cur_op;
    n_aHe = aHe; n_aLe = aLe; n_bHe = bHe; n_bLe = bLe;
    n_acc = acc;
    n_Dm = Dm; n_Bm = Bm; n_Rem = Rem; n_Q = Q;
    n_mstep = mstep; n_step = step;
    n_div_signed = div_signed; n_neg_q = neg_q; n_neg_r = neg_r;
    n_done = 1'b0;
    n_result = result;
    nr = 33'h0;
    ssub = 33'h0;

    if (reset) begin
      n_active = 1'b0;
      n_done = 1'b0;
      n_result = 32'h0;
    end else if (!active && idex_valid && is_m && !is_ill && !idex_done && !ex_stall) begin
      n_cur_op = op;
      if (op <= 3'd3) begin
        n_mulmode = 1'b1;
        n_aLe = {1'b0, aL};
        n_bLe = {1'b0, bL};
        n_aHe = ah_neg ? {aH[15], aH} : {1'b0, aH};
        n_bHe = bh_neg ? {bH[15], bH} : {1'b0, bH};
        n_acc = {30'h0, p_il};
        n_mstep = 3'd1;
        n_active = 1'b1;
      end else if (b == 32'h0) begin
        n_active = 1'b0;
        n_done = 1'b1;
        n_result = ((op == 3'd4 || op == 3'd5) ? 32'hFFFF_FFFF : a);
      end else begin
        n_mulmode = 1'b0;
        n_div_signed = (op == 3'd4 || op == 3'd6);
        n_Bm = (n_div_signed && b[31]) ? (~b + 32'h1) : b;
        n_Dm = (n_div_signed && a[31]) ? (~a + 32'h1) : a;
        n_neg_q = n_div_signed ? (a[31] ^ b[31]) : 1'b0;
        n_neg_r = n_div_signed && a[31];
        n_Rem = 32'h0;
        n_Q = 32'h0;
        n_step = 6'd0;
        n_active = 1'b1;
      end
    end else if (active) begin
      if (mulmode) begin
        case (mstep)
          3'd1: n_acc = {hl3[15:0], hl2[15:0], hl1[15:0], acc[15:0]};
          3'd2: n_acc = {lh3[15:0], lh2[15:0], lh1[15:0], acc[15:0]};
          default: begin
            n_active = 1'b0;
            n_done = 1'b1;
            n_result = (cur_op == 3'd0) ? acc[31:0] : {hh2[15:0], hh1[15:0]};
          end
        endcase
        n_mstep = mstep + 3'd1;
      end else begin
        nr = ({1'b0, Rem} << 1) | {32'b0, Dm[31]};
        n_Dm = Dm << 1;
        if (nr >= {1'b0, Bm}) begin
          ssub = nr - {1'b0, Bm};
          n_Rem = ssub[31:0];
          n_Q = (Q << 1) | 32'h1;
        end else begin
          n_Rem = nr[31:0];
          n_Q = Q << 1;
        end
        n_step = step + 6'd1;
        if (step == 6'd31) begin
          n_active = 1'b0;
          n_done = 1'b1;
          if (cur_op == 3'd4 || cur_op == 3'd5) begin
            n_result = (neg_q && (cur_op == 3'd4)) ? (~n_Q + 32'h1) : n_Q;
          end else begin
            n_result = (neg_r && (cur_op == 3'd6)) ? (~n_Rem[31:0] + 32'h1) : n_Rem[31:0];
          end
        end
      end
    end else begin
      n_active = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    active <= n_active;
    mulmode <= n_mulmode;
    cur_op <= n_cur_op;
    aHe <= n_aHe; aLe <= n_aLe; bHe <= n_bHe; bLe <= n_bLe;
    acc <= n_acc;
    Dm <= n_Dm; Bm <= n_Bm; Rem <= n_Rem; Q <= n_Q;
    mstep <= n_mstep;
    step <= n_step;
    div_signed <= n_div_signed;
    neg_q <= n_neg_q;
    neg_r <= n_neg_r;
    result <= n_result;
  end

  assign md_active = active;
  assign md_done_now = n_done;
endmodule
/* verilator lint_on TIMESCALEMOD */
/* verilator lint_on UNUSEDSIGNAL */
