// Multi-cycle M unit for pipeline: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU.
// Fast variant (simulation / M10a): MUL completes on the start cycle via 64-bit
// multiply wires; DIV/REM are 32-step restoring loops. Used when FPGA undefined.
module mdiu_fast (
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
  logic [1:0] mode = 2'b00;
  logic [2:0] cur_op = 3'd0;
  logic [31:0] m_b = 32'h0;
  logic [63:0] a_ext = 64'h0;
  logic [63:0] p = 64'h0;
  logic [63:0] div_a = 64'h0;
  logic [63:0] div_b = 64'h0;
  logic [63:0] rem = 64'h0;
  logic [63:0] q = 64'h0;
  logic [5:0] step = 6'd0;
  logic signed_a = 1'b0;
  logic signed_b = 1'b0;
  logic div_signed = 1'b0;
  logic neg_q = 1'b0;
  logic neg_r = 1'b0;

  logic n_active;
  logic n_done;
  logic [31:0] n_result;
  logic [1:0] n_mode;
  logic [2:0] n_cur_op;
  logic [31:0] n_m_b;
  logic [63:0] n_a_ext;
  logic [63:0] n_p;
  logic [63:0] n_div_a;
  logic [63:0] n_div_b;
  logic [63:0] n_rem;
  logic [63:0] n_q;
  logic [5:0] n_step;
  logic n_signed_a;
  logic n_signed_b;
  logic n_div_signed;
  logic n_neg_q;
  logic n_neg_r;
  logic [63:0] new_rem;

  // P2: the 4 multiplies (and 64-bit sign/zero extends) used to run EVERY
  // eval as top-level wires. Now computed only on M-unit start cycles; idle
  // cycles skip them (identical semantics).
  /* verilator lint_off UNUSEDSIGNAL */
  logic signed [63:0] mul_ss;
  logic signed [63:0] mul_su;
  logic [63:0] mul_uu;
  logic [31:0] mul_ll;
  /* verilator lint_on UNUSEDSIGNAL */

  // P2 sim-speed: the old always_comb copied ~20 state vars (incl 6x 64-bit)
  // EVERY cycle. Idle cycles now take a tiny path; state latches are written
  // only on start/step cycles. Semantics unchanged (the writes previously
  // rewrote identical values when idle).
  wire start = idex_valid && is_m && !is_ill && !idex_done && !ex_stall;

  always_comb begin
    n_done = 1'b0;
    n_result = result;
    if (reset) begin
      n_active = 1'b0;
    end else if (!active && start) begin
      n_mode = mode;
      n_cur_op = cur_op;
      n_m_b = m_b;
      n_p = p;
      n_div_a = div_a;
      n_div_b = div_b;
      n_rem = rem;
      n_q = q;
      n_step = step;
      n_signed_a = signed_a;
      n_signed_b = signed_b;
      n_div_signed = div_signed;
      n_neg_q = neg_q;
      n_neg_r = neg_r;
      n_a_ext = a_ext;
      n_cur_op = op;
      n_mode = op <= 3'd3 ? 2'b00 : 2'b01;
      n_signed_a = (op == 3'd1 || op == 3'd2);
      n_signed_b = (op == 3'd1);
      n_div_signed = (op == 3'd4 || op == 3'd6);
      n_neg_q = 1'b0;
      n_neg_r = 1'b0;
      n_a_ext = n_signed_a ? {{32{a[31]}}, a} : {32'h0, a};
      if (op <= 3'd3) begin
        n_m_b = b;
        n_p = 64'h0;
        n_step = 6'd0;
        n_active = 1'b0;
        n_done = 1'b1;
        mul_ll = a * b;
        mul_ss = $signed({{32{a[31]}}, a}) * $signed({{32{b[31]}}, b});
        mul_su = $signed({{32{a[31]}}, a}) * $signed({32'h0, b});
        mul_uu = {32'h0, a} * {32'h0, b};
        case (op)
          3'd0: n_result = mul_ll;
          3'd1: n_result = mul_ss[63:32];
          3'd2: n_result = mul_su[63:32];
          default: n_result = mul_uu[63:32];
        endcase
      end else if (b == 32'h0) begin
        n_active = 1'b0;
        n_done = 1'b1;
        n_result = ((op == 3'd4 || op == 3'd5) ? 32'hFFFFFFFF : a);
      end else begin
        n_div_a = n_div_signed ? {{32{a[31]}}, a} : {32'h0, a};
        n_div_b = n_div_signed ? {{32{b[31]}}, b} : {32'h0, b};
        if (n_div_signed) begin
          if (a[31]) begin
            n_div_a = ~n_div_a + 64'd1;
            n_neg_r = 1'b1;
            n_neg_q = 1'b1;
          end
          if (b[31]) begin
            n_div_b = ~n_div_b + 64'd1;
            n_neg_q = ~n_neg_q;
          end
        end
        n_rem = 64'h0;
        n_q = 64'h0;
        n_step = 6'd0;
        n_active = 1'b1;
      end
    end else if (active) begin
      n_mode = mode;
      n_cur_op = cur_op;
      n_m_b = m_b;
      n_a_ext = a_ext;
      n_div_a = div_a;
      n_div_b = div_b;
      n_signed_a = signed_a;
      n_signed_b = signed_b;
      n_div_signed = div_signed;
      n_neg_q = neg_q;
      n_neg_r = neg_r;
      n_p = p;
      n_rem = rem;
      n_q = q;
      n_step = step;
      if (mode == 2'b00) begin
        n_p = p;
        if (step < 6'd32) begin
          if (m_b[step[4:0]]) n_p = p + (a_ext << step);
          n_step = step + 6'd1;
          if (step == 6'd31 && !signed_b) begin
            n_done = 1'b1;
            n_active = 1'b0;
            n_result = (cur_op == 3'd0) ? n_p[31:0] : n_p[63:32];
          end
        end else begin
          if (signed_b && m_b[31]) n_p = p - (a_ext << 6'd32);
          n_done = 1'b1;
          n_active = 1'b0;
          n_result = (cur_op == 3'd0) ? n_p[31:0] : n_p[63:32];
        end
      end else begin
        if (step < 6'd32) begin
          new_rem = (rem << 1) | ((div_a >> (6'd31 - step)) & 64'd1);
          n_rem = new_rem;
          n_q = q;
          if (new_rem >= div_b) begin
            n_rem = new_rem - div_b;
            n_q = q | (64'd1 << (6'd31 - step));
          end
          n_step = step + 6'd1;
          if (step == 6'd31) begin
            n_done = 1'b1;
            n_active = 1'b0;
            if (div_signed) begin
              if (neg_q) n_q = -n_q;
              if (neg_r) n_rem = -n_rem;
            end
            n_result = (cur_op == 3'd4 || cur_op == 3'd5) ? n_q[31:0] : n_rem[31:0];
          end
        end else begin
          n_done = 1'b1;
          n_active = 1'b0;
          if (div_signed) begin
            if (neg_q) n_q = -n_q;
            if (neg_r) n_rem = -n_rem;
          end
          n_result = (cur_op == 3'd4 || cur_op == 3'd5) ? n_q[31:0] : n_rem[31:0];
        end
      end
    end else begin
      n_active = 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      active <= 1'b0;
      mode <= 2'b00;
      cur_op <= 3'd0;
      m_b <= 32'h0;
      a_ext <= 64'h0;
      p <= 64'h0;
      div_a <= 64'h0;
      div_b <= 64'h0;
      rem <= 64'h0;
      q <= 64'h0;
      step <= 6'd0;
      signed_a <= 1'b0;
      signed_b <= 1'b0;
      div_signed <= 1'b0;
      neg_q <= 1'b0;
      neg_r <= 1'b0;
      result <= 32'h0;
    end else if (active || start) begin
      active <= n_active;
      mode <= n_mode;
      cur_op <= n_cur_op;
      m_b <= n_m_b;
      a_ext <= n_a_ext;
      p <= n_p;
      div_a <= n_div_a;
      div_b <= n_div_b;
      rem <= n_rem;
      q <= n_q;
      step <= n_step;
      signed_a <= n_signed_a;
      signed_b <= n_signed_b;
      div_signed <= n_div_signed;
      neg_q <= n_neg_q;
      neg_r <= n_neg_r;
      result <= n_result;
    end
  end

  assign md_active = active;
  assign md_done_now = n_done;
endmodule
