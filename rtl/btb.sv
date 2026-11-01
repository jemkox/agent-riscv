// Branch target buffer with 2-bit saturating counters.
// Direct-mapped by pc[7:2]; tag is pc[31:8]. Query during fetch, update at EX.
module btb (
  input  logic        clk,
  input  logic        reset,
  input  logic        q_enable,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] q_pc,
  input  logic [31:0] upd_pc,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic        q_br,
  input  logic        q_jal,
  input  logic        q_jalr,
  output logic        q_valid,
  output logic        q_taken,
  output logic [31:0] q_target,
  output logic [31:0] out_branches,
  output logic [31:0] out_taken_preds,
  output logic [31:0] out_mispreds,
  input  logic        upd_enable,
  input  logic        upd_taken,
  input  logic [31:0] upd_target,
  input  logic        upd_pred_taken,
  input  logic        upd_mispred
);
  localparam N = 64;
  logic valid [0:N-1];
  logic [23:0] tag [0:N-1];
  logic [31:0] tgt [0:N-1];
  logic [1:0]  cnt [0:N-1];
  logic [5:0] qi, ui;
  logic [31:0] branches_cnt = 0, taken_cnt = 0, misp_cnt = 0;

  assign qi = q_pc[7:2];
  assign ui = upd_pc[7:2];

  always_comb begin
    q_valid = 1'b0;
    q_taken = 1'b0;
    q_target = 32'h0;
    if (q_enable && valid[qi] && (tag[qi] == q_pc[31:8])) begin
      q_valid = 1'b1;
      q_target = tgt[qi] & 32'hFFFFFFFE;
      if (q_jal || q_jalr || (q_br && (cnt[qi] == 2'd3))) q_taken = 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      branches_cnt <= 32'h0;
      taken_cnt <= 32'h0;
      misp_cnt <= 32'h0;
      for (int k = 0; k < N; k++) begin
        valid[k] <= 1'b0;
        tag[k] <= 24'h0;
        tgt[k] <= 32'h0;
        cnt[k] <= 2'd0;
      end
    end else begin
      if (upd_enable) begin
        branches_cnt <= branches_cnt + 32'd1;
        if (upd_pred_taken) taken_cnt <= taken_cnt + 32'd1;
        if (upd_mispred) misp_cnt <= misp_cnt + 32'd1;
        if (valid[ui] && (tag[ui] == upd_pc[31:8])) begin
          if (upd_taken) begin
            if (cnt[ui] < 2'd3) cnt[ui] <= cnt[ui] + 2'd1;
          end else if (cnt[ui] > 2'd0) begin
            cnt[ui] <= cnt[ui] - 2'd1;
          end
          tgt[ui] <= upd_target & 32'hFFFFFFFE;
        end else begin
          valid[ui] <= 1'b1;
          tag[ui] <= upd_pc[31:8];
          tgt[ui] <= upd_target & 32'hFFFFFFFE;
          cnt[ui] <= upd_taken ? 2'd2 : 2'd1;
        end
      end
    end
  end

  assign out_branches = branches_cnt;
  assign out_taken_preds = taken_cnt;
  assign out_mispreds = misp_cnt;
endmodule
