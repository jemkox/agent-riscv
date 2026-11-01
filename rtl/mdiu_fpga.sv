// MDU for the FPGA build (option b per review): small schoolbook unit.
// MUL uses one 65-bit adder (A<<=1; if B[0] P +/-= A; MULH correction P-=A);
// DIV/REM use a 33-bit restoring remainder.  Latency ~33 cycles for all ops.
// The SIM build uses rtl/mdiu_fast.sv instead (single-cycle MUL wires).
/* verilator lint_off TIMESCALEMOD */
/* verilator lint_off UNUSEDSIGNAL */
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
  logic mulmode = 1'b0;      // 1 = multiply loop, 0 = divide loop
  logic [2:0] cur_op = 3'd0;
  logic [64:0] A = 65'h0;    // 65-bit multiplicand (sign/zero extended per op)
  logic [31:0] B = 32'h0;    // multiplier, shifted right each step
  logic [64:0] P = 65'h0;    // partial product
  logic [31:0] Dm = 32'h0;   // dividend magnitude, shifted left
  logic [31:0] Bm = 32'h0;   // divisor magnitude
  logic [31:0] Rem = 32'h0;
  logic [31:0] Q = 32'h0;
  logic [5:0] step = 6'd0;
  logic div_signed = 1'b0;
  logic neg_q = 1'b0;
  logic neg_r = 1'b0;

  logic n_active;
  logic n_mulmode;
  logic [2:0] n_cur_op;
  logic [64:0] n_A;
  logic [31:0] n_B;
  logic [64:0] n_P;
  logic [31:0] n_Dm;
  logic [31:0] n_Bm;
  logic [31:0] n_Rem;
  logic [31:0] n_Q;
  logic [5:0] n_step;
  logic n_div_signed;
  logic n_neg_q;
  logic n_neg_r;
  logic n_done;
  logic [31:0] n_result;
  logic [32:0] nr;
  logic [32:0] ssub;

  always_comb begin
    n_active = active;
    n_mulmode = mulmode;
    n_cur_op = cur_op;
    n_A = A;
    n_B = B;
    n_P = P;
    n_Dm = Dm;
    n_Bm = Bm;
    n_Rem = Rem;
    n_Q = Q;
    n_step = step;
    n_div_signed = div_signed;
    n_neg_q = neg_q;
    n_neg_r = neg_r;
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
        case (op)
          3'd1, 3'd2: n_A = {{1{a[31]}}, {32{a[31]}}, a};
          3'd3: n_A = {1'b0, 32'h0, a};
          default: n_A = {1'b0, 32'h0, a};
        endcase
        n_B = b;
        n_P = 65'h0;
        n_step = 6'd0;
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
        if (B[0]) begin
          if (step == 6'd31 && cur_op == 3'd1) n_P = P - A;
          else n_P = P + A;
        end
        n_A = A << 1;
        n_B = B >> 1;
        n_step = step + 6'd1;
        if (step == 6'd31) begin
          n_active = 1'b0;
          n_done = 1'b1;
          n_result = (cur_op == 3'd0) ? n_P[31:0] : n_P[63:32];
        end
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
    A <= n_A;
    B <= n_B;
    P <= n_P;
    Dm <= n_Dm;
    Bm <= n_Bm;
    Rem <= n_Rem;
    Q <= n_Q;
    step <= n_step;
    div_signed <= n_div_signed;
    neg_q <= n_neg_q;
    neg_r <= n_neg_r;
    result <= n_result;
  end

  assign md_active = active;
  assign md_done_now = n_done;
endmodule
