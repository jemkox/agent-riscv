// Multi-cycle M unit for pipeline: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU.
module mdiu (
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

  /* verilator lint_off UNUSEDSIGNAL */
  wire signed [63:0] a_s64 = {{32{a[31]}}, a};
  wire signed [63:0] b_s64 = {{32{b[31]}}, b};
  wire [63:0] a_u64 = {32'h0, a};
  wire [63:0] b_u64 = {32'h0, b};
  wire signed [63:0] mul_ss = a_s64 * $signed(b_s64);
  wire signed [63:0] mul_su = a_s64 * $signed(b_u64);
  wire [63:0] mul_uu = a_u64 * b_u64;
  wire [31:0] mul_ll = a * b;
  /* verilator lint_on UNUSEDSIGNAL */

  always_comb begin
    n_active = active;
    n_done = 1'b0;
    n_result = result;
    n_mode = mode;
    n_cur_op = cur_op;
    n_m_b = m_b;
    n_a_ext = a_ext;
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
    new_rem = 64'h0;

    if (reset) begin
      n_active = 1'b0;
      n_mode = 2'b00;
      n_result = 32'h0;
      n_done = 1'b0;
    end else if (!active && idex_valid && is_m && !is_ill && !idex_done && !ex_stall) begin
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

  assign md_active = active;
  assign md_done_now = n_done;
endmodule
